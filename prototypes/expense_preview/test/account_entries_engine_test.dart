import 'dart:io';

import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';

void main() {
  final root = Directory('.dart_tool/account-entries-engine')
    ..createSync(recursive: true);

  test('account entries use an independent keyset and include transfer destination', () async {
    final work = root.createTempSync('case-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 24);
    try {
      await setup(engine);
      final source = account(engine, name: '分頁來源');
      final destination = account(engine, name: '轉入目的');
      await engine.createAccount(source, opening(source));
      await engine.createAccount(destination, opening(destination));

      final expectedSourceIds = <PublicId>[];
      for (var day = 1; day <= 31; day++) {
        final current = (await engine.accounts())
            .singleWhere((row) => row.account.id == source.id)
            .account;
        final id = PublicId.generate();
        expectedSourceIds.add(id);
        await engine.post(
          Posting.expense(
            id: id,
            operation: OperationKey(
              engine.workspace,
              OperationId(PublicId.generate()),
            ),
            date: BusinessDate(2026, 1, day),
            account: ref(current),
            amount: Money.parse(current.currency, '1'),
          ),
        );
      }

      final accounts = await engine.accounts();
      final currentSource = accounts
          .singleWhere((row) => row.account.id == source.id)
          .account;
      final currentDestination = accounts
          .singleWhere((row) => row.account.id == destination.id)
          .account;
      final transferId = PublicId.generate();
      await engine.post(
        Posting.transfer(
          id: transferId,
          operation: OperationKey(
            engine.workspace,
            OperationId(PublicId.generate()),
          ),
          date: BusinessDate(2026, 2, 1),
          source: ref(currentSource),
          destination: ref(currentDestination),
          principal: Money.parse(currentSource.currency, '2'),
          received: Money.parse(currentDestination.currency, '2'),
          fee: Money.parse(currentSource.currency, '0'),
        ),
      );

      final first = await engine.accountEntries(source.id);
      final second = await engine.accountEntries(source.id, before: first.last);
      expect(first, hasLength(30));
      expect(second, hasLength(3));
      expect(
        first
            .map((entry) => entry.id)
            .toSet()
            .intersection(second.map((entry) => entry.id).toSet()),
        isEmpty,
      );
      expect(
        [...first, ...second].map((entry) => entry.id).toSet(),
        containsAll({...expectedSourceIds, transferId}),
      );

      final destinationRows = await engine.accountEntries(destination.id);
      final transfer = destinationRows.singleWhere(
        (entry) => entry.id == transferId,
      );
      expect(transfer.accountId, source.id);
      expect(transfer.destinationId, destination.id);
      expect(transfer.received?.majorText, '2.00');
      await engine.lock();
      await expectLater(
        engine.accountEntries(source.id),
        throwsA(isA<PreviewLocked>()),
      );
    } finally {
      if (engine.isUnlocked) await engine.lock();
      deleteSynthetic(work, root);
    }
  });
}
