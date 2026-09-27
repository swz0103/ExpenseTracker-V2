import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:foundation_values/foundation_values.dart';
import 'package:storage_generation_probe/catalog_protection.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:storage_generation_probe/generation_store.dart';
import 'package:storage_generation_probe/lock_wait.dart';
import 'package:test/test.dart';

final class HeldLock {
  HeldLock(this.process);
  final Process process;
  bool closed = false;
  Future<void> release() async {
    if (closed) return;
    closed = true;
    process.stdin.writeln('release');
    await process.stdin.flush();
    await process.stdin.close();
    expect(await process.exitCode.timeout(const Duration(seconds: 15)), 0);
  }
}

void main() {
  final parent = Directory('.dart_tool/lock-tests')
    ..createSync(recursive: true);
  late Directory owned;
  late Directory root;
  late FixtureKeySlots slots;
  late CatalogProtection protection;
  late GenerationStore store;
  var loads = 0;
  HeldLock? held;
  GenerationStore open([Duration timeout = const Duration(seconds: 2)]) =>
      GenerationStore(
        root,
        slots,
        catalogProtection: protection,
        lockTimeout: timeout,
      );
  OperationId operation() => OperationId(PublicId.generate());
  Matcher problem(GenerationProblem value) =>
      isA<GenerationUnavailable>().having((e) => e.problem, 'problem', value);
  setUp(() {
    loads = 0;
    held = null;
    owned = parent.createTempSync('case-');
    root = Directory('${owned.path}/store');
    slots = FixtureKeySlots(Directory('${root.path}-keys'));
    final delegate = fixtureCatalogProtection(slots);
    protection = CatalogProtection(delegate.identity, (exists) {
      loads++;
      return delegate.loadKey(exists);
    });
    store = open();
  });
  tearDown(() async {
    await held?.release();
    if (!owned.absolute.path.startsWith(
      '${parent.absolute.path}${Platform.pathSeparator}',
    ))
      throw StateError('Unsafe cleanup');
    owned.deleteSync(recursive: true);
  });
  Future<void> hold() async {
    final exe = File(
      '.dart_tool/worker/bundle/bin/generation_worker${Platform.isWindows ? '.exe' : ''}',
    );
    final process = await Process.start(exe.absolute.path, [
      'hold',
      root.absolute.path,
      '-',
      '-',
      '-',
      'protected',
    ]);
    held = HeldLock(process);
    process.stderr.drain<void>();
    expect(
      await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 15)),
      'locked',
    );
  }

  test(
    'pre-cancelled install does not create a directory, catalog or key',
    () async {
      final token = LockWaitCancellation()..cancel();
      await expectLater(
        store.install('new', operation(), cancellation: token),
        throwsA(problem(GenerationProblem.lockCancelled)),
      );
      expect(root.existsSync(), isFalse);
      expect(slots.directory.existsSync(), isFalse);
      expect(loads, 0);
    },
  );
  test(
    'timeout leaves existing catalog and keys untouched and permits retry',
    () async {
      await store.install('old', operation());
      final file = File('${root.path}/catalog.db');
      final before = file.readAsBytesSync();
      final keys = slots.directory.listSync().length;
      final baselineLoads = loads;
      await hold();
      final op = operation();
      final elapsed = Stopwatch()..start();
      await expectLater(
        open(const Duration(milliseconds: 120)).install('new', op),
        throwsA(problem(GenerationProblem.lockTimeout)),
      );
      expect(elapsed.elapsed, lessThan(const Duration(seconds: 5)));
      expect(loads, baselineLoads);
      expect(file.readAsBytesSync(), before);
      expect(slots.directory.listSync().length, keys);
      await held!.release();
      await store.install('new', op);
      expect((await store.current())!.value, 'new');
    },
  );
  test('cancelling an active wait never opens the protected catalog', () async {
    await store.install('old', operation());
    final before = File('${root.path}/catalog.db').readAsBytesSync();
    final baselineLoads = loads;
    await hold();
    final token = LockWaitCancellation();
    final timer = Timer(const Duration(milliseconds: 80), token.cancel);
    try {
      await expectLater(
        store.install('new', operation(), cancellation: token),
        throwsA(problem(GenerationProblem.lockCancelled)),
      );
    } finally {
      timer.cancel();
    }
    expect(loads, baselineLoads);
    expect(File('${root.path}/catalog.db').readAsBytesSync(), before);
    await held!.release();
    expect((await store.current())!.value, 'old');
  });
  test('wait proceeds when another process releases within deadline', () async {
    await store.install('old', operation());
    await hold();
    final release = Future<void>.delayed(
      const Duration(milliseconds: 150),
      held!.release,
    );
    await store.install('new', operation());
    await release;
    expect((await store.current())!.value, 'new');
  });
  test(
    'zero timeout performs one attempt and releases guards on contention',
    () async {
      await hold();
      await expectLater(
        open(Duration.zero).current(),
        throwsA(problem(GenerationProblem.lockTimeout)),
      );
      expect(loads, 0);
      await held!.release();
      expect(await open(Duration.zero).current(), isNull);
    },
  );
  test('fresh blocked initialization creates no catalog or key', () async {
    await hold();
    await expectLater(
      open(const Duration(milliseconds: 75)).current(),
      throwsA(problem(GenerationProblem.lockTimeout)),
    );
    expect(File('${root.path}/catalog.db').existsSync(), isFalse);
    expect(slots.directory.existsSync(), isFalse);
    expect(loads, 0);
  });
  test('negative timeout is rejected before opening storage', () {
    expect(() => open(const Duration(milliseconds: -1)), throwsArgumentError);
    expect(root.existsSync(), isFalse);
  });
  for (final point in ['reserved', 'published']) {
    test(
      'cancellation after acquisition at $point does not imply rollback',
      () async {
        final token = LockWaitCancellation();
        final receipt = await store.install(
          'committed',
          operation(),
          cancellation: token,
          checkpoint: (at) {
            if (at == point) token.cancel();
          },
        );
        expect(token.isCancelled, isTrue);
        expect((await store.current())!.receipt.generation, receipt.generation);
      },
    );
  }
  test(
    'cancelled read and scoped work do not load keys or run callbacks',
    () async {
      await store.install('old', operation());
      final baselineLoads = loads;
      final token = LockWaitCancellation()..cancel();
      await expectLater(
        store.current(cancellation: token),
        throwsA(problem(GenerationProblem.lockCancelled)),
      );
      var ran = false;
      await expectLater(
        store.withCurrent((_, _, _) async {
          ran = true;
        }, cancellation: token),
        throwsA(problem(GenerationProblem.lockCancelled)),
      );
      expect(ran, isFalse);
      expect(loads, baselineLoads);
    },
  );
  test('non-contention I/O failure is not retried as a busy lock', () async {
    final file = await File('${owned.path}/closed.lock')
        .open(mode: FileMode.append);
    await file.close();
    final elapsed = Stopwatch()..start();
    await expectLater(
      acquireLifecycleLock(file, timeout: const Duration(seconds: 10)),
      throwsA(isA<FileSystemException>()),
    );
    expect(elapsed.elapsed, lessThan(const Duration(seconds: 2)));
  });
}
