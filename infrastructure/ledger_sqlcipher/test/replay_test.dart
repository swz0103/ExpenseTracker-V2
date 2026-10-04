import 'dart:io';

import 'package:foundation_values/foundation_values.dart';
import 'package:ledger_sqlcipher/ledger_sqlcipher.dart';
import 'package:ledger_sqlcipher/testing.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  final workspace = WorkspaceId(PublicId.generate());

  setUp(() {
    directory = Directory.systemTemp.createTempSync('ledger-replay-');
  });

  tearDown(() => directory.deleteSync(recursive: true));

  SqlCipherStore open(String name) => SqlCipherStore.open(
    File('${directory.path}/$name.db'),
    StorageKey.random(),
    modules: [ledgerSchema],
  );

  test('replaying the journal rebuilds every projection exactly', () async {
    final source = open('source');
    final target = open('target');
    addTearDown(source.close);
    addTearDown(target.close);
    await EveryEventKind(workspace).fill(LedgerStore(source));

    final copied = await LedgerReplay.copy(
      from: source,
      to: LedgerStore(target),
      batch: 7,
    );
    expect(copied, source.eventCount);
    expect(target.eventCount, source.eventCount);
    expect(target.operationCount, source.operationCount);
    expect(projectionRows(target), projectionRows(source));
    expect(
      target.journal(limit: 1000).map((e) => '${e.seq}/${e.id}/${e.kind}'),
      source.journal(limit: 1000).map((e) => '${e.seq}/${e.id}/${e.kind}'),
    );
    expect(target.integrityCheck(), 'ok');
  });

  test('an event the replayer does not know stops the replay', () async {
    final source = open('source');
    final target = open('target');
    addTearDown(source.close);
    addTearDown(target.close);
    await source.write((transaction) async {
      transaction.append(
        id: PublicId.generate(),
        workspace: workspace,
        kind: 'mystery.changed',
        payload: '{}',
      );
    });
    await expectLater(
      LedgerReplay.copy(from: source, to: LedgerStore(target)),
      throwsA(
        isA<ReplayException>()
            .having((e) => e.kind, 'kind', 'mystery.changed')
            .having((e) => e.seq, 'seq', 1),
      ),
    );
    expect(target.eventCount, 0);
  });

  test('a payload that breaks a domain rule stops the replay', () async {
    final source = open('source');
    final target = open('target');
    addTearDown(source.close);
    addTearDown(target.close);
    await source.write((transaction) async {
      transaction.append(
        id: PublicId.generate(),
        workspace: workspace,
        kind: 'account.opened',
        payload: '{"version":1,"name":""}',
      );
    });
    await expectLater(
      LedgerReplay.copy(from: source, to: LedgerStore(target)),
      throwsA(
        isA<ReplayException>().having((e) => e.kind, 'kind', 'account.opened'),
      ),
    );
  });
}
