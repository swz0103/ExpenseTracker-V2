import 'dart:io';

import 'package:data_exchange/data_exchange.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';

void main() {
  final root = Directory('.dart_tool/simple-import-engine-tests')
    ..createSync(recursive: true);

  for (final recovery in [false, true]) {
    test(
      'review requires confirmation and replay survives clean ${recovery ? 'recovery' : 'password'} restore',
      () async {
        final work = root.createTempSync('case-');
        final source = engineAt(
          Directory('${work.path}/source'),
          MemoryVault(),
          schemaVersion: 12,
        );
        final target = engineAt(
          Directory('${work.path}/target'),
          MemoryVault(),
          schemaVersion: 12,
        );
        try {
          final recoveryKey = await setup(source);
          final cash = account(source);
          await source.createAccount(cash, opening(cash));
          final foreignAccount = PublicId.generate();
          final batch = SimpleTransactionBatch(
            WorkspaceId(PublicId.generate()),
            [
              SimpleTransaction(
                sourceRecordId: PublicId.generate(),
                date: BusinessDate(2026, 9, 28),
                kind: PostingKind.income,
                accountId: foreignAccount,
                amount: Money.parse(cash.currency, '12.34'),
                note: 'Imported exactly once',
              ),
              SimpleTransaction(
                sourceRecordId: PublicId.generate(),
                date: BusinessDate(2026, 9, 28),
                kind: PostingKind.expense,
                accountId: foreignAccount,
                amount: Money.parse(cash.currency, '2'),
              ),
            ],
          );
          final mapping = {foreignAccount: cash.id};
          final jsonReview = await source.reviewSimpleImport(
            SimpleTransactionCodec.encodeJson(batch),
            csv: false,
            accountMapping: mapping,
          );
          expect(jsonReview.preview.rows, hasLength(2));
          expect(
            (await source.accounts()).single.balance.minorUnits,
            BigInt.from(10000),
          );
          final committed = await source.confirmSimpleImport(jsonReview);
          expect(committed.inserted, 2);
          expect(committed.replayed, 0);
          expect(
            (await source.accounts()).single.balance.minorUnits,
            BigInt.from(11034),
          );
          final backup = await source.exportBackup();
          final csv = SimpleTransactionCodec.encodeCsv(batch);
          final csvReview = await source.reviewSimpleImport(
            csv,
            csv: true,
            accountMapping: mapping,
          );
          final replay = await source.confirmSimpleImport(csvReview);
          expect(replay.entryIds, committed.entryIds);
          expect(replay.replayed, 2);
          expect(await source.exportBackup(), isNotEmpty);

          await source.lock();
          await source.unlock(password);
          await expectLater(
            source.confirmSimpleImport(csvReview),
            throwsA(isA<PreviewInvalid>()),
          );

          await setup(target);
          await target.importBackup(
            backup,
            recovery ? recoveryKey : password,
            recovery: recovery,
          );
          final restoredReview = await target.reviewSimpleImport(
            csv,
            csv: true,
            accountMapping: mapping,
          );
          final restoredReplay = await target.confirmSimpleImport(
            restoredReview,
          );
          expect(restoredReplay.entryIds, committed.entryIds);
          expect(restoredReplay.inserted, 0);
          expect(restoredReplay.replayed, 2);
          expect(
            (await target.accounts()).single.balance.minorUnits,
            BigInt.from(11034),
          );
          expect((await target.entries()), hasLength(3));
          expect(
            (await target.entryNote(committed.entryIds.first)).text,
            'Imported exactly once',
          );
        } finally {
          await source.lock();
          await target.lock();
          deleteSynthetic(work, root);
        }
      },
    );
  }

  test('simple export round-trips ordinary income and expense into another V2 book', () async {
    final work = root.createTempSync('export-');
    final source = engineAt(
      Directory('${work.path}/source'),
      MemoryVault(),
      schemaVersion: 12,
    );
    final target = engineAt(
      Directory('${work.path}/target'),
      MemoryVault(),
      schemaVersion: 12,
    );
    try {
      await setup(source);
      final cash = account(source);
      await source.createAccount(cash, opening(cash));
      await source.post(income(cash));
      await source.post(
        Posting.expense(
          id: PublicId.generate(),
          operation: OperationKey(
            source.workspace,
            OperationId(PublicId.generate()),
          ),
          date: BusinessDate(2026, 9, 28),
          account: ref(cash),
          amount: Money.parse(cash.currency, '2.50'),
        ),
      );
      final export = await source.reviewSimpleExport();
      expect(export.openingCount, 1);
      expect(export.unsupportedCount, 0);
      expect(export.includedCount, 2);
      expect(export.batch.sourceWorkspace, source.workspace);
      expect(export.batch.records.map((row) => row.kind).toSet(), {
        PostingKind.income,
        PostingKind.expense,
      });
      final csv = export.toCsv();
      final json = export.toJson();
      expect(SimpleTransactionCodec.decodeCsv(csv).records, hasLength(2));
      expect(SimpleTransactionCodec.decodeJson(json).records, hasLength(2));
      await expectLater(
        source.reviewSimpleImport(
          json,
          csv: false,
          accountMapping: {cash.id: cash.id},
        ),
        throwsA(
          isA<ExchangeException>().having(
            (error) => error.code,
            'code',
            'same_workspace_import',
          ),
        ),
      );
      expect(
        (await source.accounts()).single.balance.minorUnits,
        BigInt.from(10450),
      );

      final transferTarget = account(source, name: 'Other source account');
      await source.createAccount(transferTarget, opening(transferTarget));
      await source.post(
        Posting.transfer(
          id: PublicId.generate(),
          operation: OperationKey(
            source.workspace,
            OperationId(PublicId.generate()),
          ),
          date: BusinessDate(2026, 9, 28),
          source: ref(cash),
          destination: ref(transferTarget),
          principal: Money.parse(cash.currency, '1'),
          received: Money.parse(cash.currency, '1'),
          fee: Money.parse(cash.currency, '0.10'),
        ),
      );
      final partial = await source.reviewSimpleExport();
      expect(partial.includedCount, 2);
      expect(partial.openingCount, 2);
      expect(partial.unsupportedCount, 1);

      await setup(target);
      final targetCash = account(target);
      await target.createAccount(targetCash, opening(targetCash));
      final review = await target.reviewSimpleImport(
        csv,
        csv: true,
        accountMapping: {cash.id: targetCash.id},
      );
      final imported = await target.confirmSimpleImport(review);
      expect(imported.inserted, 2);
      expect(imported.replayed, 0);
      expect(
        (await target.accounts()).single.balance.minorUnits,
        BigInt.from(10450),
      );
      expect((await target.entries()), hasLength(3));
    } finally {
      await source.lock();
      await target.lock();
      deleteSynthetic(work, root);
    }
  });
}
