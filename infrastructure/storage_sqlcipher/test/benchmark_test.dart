import 'dart:convert';
import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';
import 'package:test/test.dart';

final class _Append implements Command<int> {
  _Append(this.operation);

  @override
  final OperationKey operation;

  @override
  String get input => 'bench-v1';

  @override
  String encodeResult(int result) => '$result';

  @override
  int decodeResult(String encoded) => int.parse(encoded);
}

const _events = 100000;
const _batch = 1000;
const _payload =
    '{"amount":"1234.56","currency":"TWD","account":"0190f3c2-7e4b-7c1a'
    '-9d2e-3f4a5b6c7d8e","category":"food","note":"lunch with team"}';

Duration _time(void Function() body) {
  final watch = Stopwatch()..start();
  body();
  return watch.elapsed;
}

void main() {
  test('100k events stay fast to write, page and reopen', () async {
    final directory = Directory.systemTemp.createTempSync('sqlcipher-bench-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/ledger.db');
    final key = StorageKey.random();
    final workspace = WorkspaceId(PublicId.generate());
    var store = SqlCipherStore.open(file, key);

    final write = Stopwatch()..start();
    for (var done = 0; done < _events; done += _batch) {
      await store.write((transaction) async {
        for (var i = 0; i < _batch; i++) {
          transaction.append(
            id: PublicId.generate(),
            workspace: workspace,
            kind: 'bench.appended',
            payload: _payload,
          );
        }
      });
    }
    write.stop();
    expect(store.eventCount, _events);

    final runner = CommandRunner(store);
    final latencies = <int>[];
    for (var i = 0; i < 200; i++) {
      final id = OperationId(PublicId.generate());
      final operation = OperationKey(workspace, id);
      final watch = Stopwatch()..start();
      await runner.run(_Append(operation), (transaction) async {
        return transaction.append(
          id: PublicId.generate(),
          workspace: workspace,
          kind: 'bench.command',
          payload: _payload,
        );
      });
      latencies.add(watch.elapsedMicroseconds);
    }
    latencies.sort();
    final index = (latencies.length * 95) ~/ 100;
    final p95 = Duration(microseconds: latencies[index]);

    final tail = _time(() => store.events(workspace, afterSeq: _events - 500));
    store.close();
    final reopen = _time(() => store = SqlCipherStore.open(file, key));
    late String integrity;
    final check = _time(() => integrity = store.integrityCheck());
    store.close();

    final megabytes = file.lengthSync() / (1024 * 1024);
    print(
      'bench: write ${write.elapsed.inMilliseconds} ms, '
      'command p95 ${p95.inMicroseconds} us, '
      'tail page ${tail.inMicroseconds} us, '
      'reopen ${reopen.inMilliseconds} ms, '
      'integrity ${check.inMilliseconds} ms, '
      'file ${megabytes.toStringAsFixed(1)} MiB',
    );
    _record('storage_bench', {
      'writeMs': write.elapsed.inMilliseconds,
      'p95Us': p95.inMicroseconds,
      'tailUs': tail.inMicroseconds,
      'reopenMs': reopen.inMilliseconds,
      'integrityMs': check.inMilliseconds,
      'fileKiB': file.lengthSync() ~/ 1024,
    });
    expect(integrity, 'ok');
    // Generous ceilings: they catch a lost index or an accidental full scan,
    // not normal CI noise.
    expect(write.elapsed, lessThan(const Duration(seconds: 90)));
    expect(p95, lessThan(const Duration(milliseconds: 250)));
    expect(tail, lessThan(const Duration(milliseconds: 100)));
    expect(reopen, lessThan(const Duration(seconds: 3)));
  });
}

/// Keeps the numbers as a CI artifact when `BENCHMARK_DIR` is set, so runs
/// can be compared over time (code audit P3).
void _record(String name, Map<String, int> metrics) {
  final directory = Platform.environment['BENCHMARK_DIR'];
  if (directory == null || directory.isEmpty) return;
  File('$directory/$name.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(metrics));
}
