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
}
