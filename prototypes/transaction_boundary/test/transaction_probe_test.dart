import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:transaction_boundary_probe/transaction_probe.dart';

void main() {
  late Directory fixture;
  late String databasePath;
  final fixtureRoot = Directory('.dart_tool/probe-tests')
    ..createSync(recursive: true);

  setUp(() {
    fixture = fixtureRoot.createTempSync('tx-');
    databasePath = '${fixture.path}/probe.db';
    TransactionProbe(databasePath).close();
  });

  tearDown(() {
    final root = fixtureRoot.resolveSymbolicLinksSync();
    final target = fixture.resolveSymbolicLinksSync();
    if (!target.startsWith('$root${Platform.pathSeparator}')) {
      throw StateError('Refusing cleanup outside the test fixture root.');
    }
    fixture.deleteSync(recursive: true);
  });

  void expectState({int operations = 0, int legs = 0, int receipts = 0}) {
    final probe = TransactionProbe(databasePath);
    try {
      for (final entry in {
        'business_operations': operations,
        'ledger_legs': legs,
        'operation_receipts': receipts,
      }.entries) {
        expect(
          probe.database
              .select('SELECT COUNT(*) AS n FROM ${entry.key}')
              .single['n'],
          entry.value,
        );
      }
      expect(
        probe.database
            .select(
              'SELECT COALESCE(SUM(minor_units), 0) AS n FROM ledger_legs',
            )
            .single['n'],
        0,
      );
      expect(probe.database.select('PRAGMA foreign_key_check'), isEmpty);
      expect(
        probe.database.select('PRAGMA integrity_check').single.values.single,
        'ok',
      );
    } finally {
      probe.close();
    }
  }

  Future<ProcessResult> worker(String checkpoint) => Process.run(
    File('.dart_tool/worker/bundle/bin/worker.exe').absolute.path,
    [databasePath, 'workspace-a', 'transfer-1', '2500', checkpoint],
    workingDirectory: Directory.current.path,
  );

  for (final checkpoint in Checkpoint.values.where(
    (value) => value != Checkpoint.committed,
  )) {
    test('TX-01 rolls back every table after ${checkpoint.name}', () {
      final probe = TransactionProbe(databasePath);
      try {
        expect(
          () => probe.transfer(
            workspaceId: 'workspace-a',
            operationId: 'transfer-1',
            minorUnits: 2500,
            onCheckpoint: (current) {
              if (current == checkpoint) throw StateError('injected');
            },
          ),
          throwsStateError,
        );
      } finally {
        probe.close();
      }
      expectState();
    });
  }

  test('TX-02 reopens and replays a committed result without extra legs', () {
    var probe = TransactionProbe(databasePath);
    final first = probe.transfer(
      workspaceId: 'workspace-a',
      operationId: 'transfer-1',
      minorUnits: 2500,
    );
    expect(first.replayed, isFalse);
    probe.close();
    probe = TransactionProbe(databasePath);
    try {
      final replay = probe.transfer(
        workspaceId: 'workspace-a',
        operationId: 'transfer-1',
        minorUnits: 2500,
      );
      expect(replay.operationId, first.operationId);
      expect(replay.replayed, isTrue);
      final rows = probe.database.select(
        'SELECT side, minor_units FROM ledger_legs ORDER BY side',
      );
      expect(rows.map((row) => row['minor_units']).toList(), [2500, -2500]);
    } finally {
      probe.close();
    }
    expectState(operations: 1, legs: 2, receipts: 1);
  });

  test(
    'TX-03 rejects changed input but allows a new same-amount intention',
    () {
      final probe = TransactionProbe(databasePath);
      try {
        probe.transfer(
          workspaceId: 'workspace-a',
          operationId: 'transfer-1',
          minorUnits: 2500,
        );
        expect(
          () => probe.transfer(
            workspaceId: 'workspace-a',
            operationId: 'transfer-1',
            minorUnits: 3000,
          ),
          throwsA(isA<OperationConflict>()),
        );
        expect(
          probe
              .transfer(
                workspaceId: 'workspace-a',
                operationId: 'transfer-2',
                minorUnits: 2500,
              )
              .replayed,
          isFalse,
        );
      } finally {
        probe.close();
      }
      expectState(operations: 2, legs: 4, receipts: 2);
    },
  );

  test('operation identity is scoped to the workspace', () {
    final probe = TransactionProbe(databasePath);
    try {
      for (final workspace in ['workspace-a', 'workspace-b']) {
        expect(
          probe
              .transfer(
                workspaceId: workspace,
                operationId: 'transfer-1',
                minorUnits: 2500,
              )
              .replayed,
          isFalse,
        );
      }
    } finally {
      probe.close();
    }
    expectState(operations: 2, legs: 4, receipts: 2);
  });

  test('invalid input leaves no financial data', () {
    final probe = TransactionProbe(databasePath);
    try {
      expect(
        () => probe.transfer(
          workspaceId: 'workspace-a',
          operationId: 'transfer-1',
          minorUnits: 0,
        ),
        throwsArgumentError,
      );
    } finally {
      probe.close();
    }
    expectState();
  });

  test(
    'TX-06 abrupt process exit before commit recovers without half a transfer',
    () async {
      final result = await worker('debit');
      expect(result.exitCode, 73, reason: '${result.stdout}\n${result.stderr}');
      expectState();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('TX-02 abrupt exit after commit retains one result for retry', () async {
    final result = await worker('committed');
    expect(result.exitCode, 73, reason: '${result.stdout}\n${result.stderr}');
    expectState(operations: 1, legs: 2, receipts: 1);
    final retry = await worker('none');
    expect(retry.exitCode, 0, reason: '${retry.stdout}\n${retry.stderr}');
    expect(jsonDecode((retry.stdout as String).trim())['replayed'], isTrue);
    expectState(operations: 1, legs: 2, receipts: 1);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'concurrent processes committing the same operation produce one result',
    () async {
      final results = await Future.wait([worker('none'), worker('none')]);
      for (final result in results) {
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      }
      final replayFlags = results
          .map(
            (result) =>
                jsonDecode((result.stdout as String).trim())['replayed'],
          )
          .toList();
      expect(replayFlags, unorderedEquals([false, true]));
      expectState(operations: 1, legs: 2, receipts: 1);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
