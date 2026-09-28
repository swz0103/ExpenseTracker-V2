import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:categories/categories.dart';
import 'package:data_exchange/data_exchange.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';

OperationKey _operation(PreviewEngine engine) =>
    OperationKey(engine.workspace, OperationId(PublicId.generate()));

void main() {
  final root = Directory('.dart_tool/combined-authority-backup-gate')
    ..createSync(recursive: true);

  for (final recovery in [false, true]) {
    test('schema 14 combined authority survives clean '
        '${recovery ? 'recovery' : 'password'} restore and replay', () async {
      final sourceDir = root.createTempSync('source-');
      final targetDir = root.createTempSync('target-');
      final source = engineAt(sourceDir, MemoryVault(), schemaVersion: 14);
      final target = engineAt(targetDir, MemoryVault(), schemaVersion: 14);
      try {
        final sourceKey = await setup(source);
        final a = account(source);
        await source.createAccount(a, opening(a));

        final parent = PublicId.generate();
        final child = PublicId.generate();
        final tag = PublicId.generate();
        final merchant = PublicId.generate();
        await source.createCategory(
          _operation(source),
          parent,
          'Household',
          CategoryKind.expense,
        );
        await source.createCategory(
          _operation(source),
          child,
          'Groceries',
          CategoryKind.expense,
          parentId: parent,
        );
        await source.createTag(_operation(source), tag, 'Essential');
        await source.createMerchant(_operation(source), merchant, 'Market');

        final classified = Posting.expense(
          id: PublicId.generate(),
          operation: _operation(source),
          date: BusinessDate(2026, 9, 29),
          account: ref(a),
          amount: Money.parse(a.currency, '5'),
          allocations: [
            Allocation(
              child,
              Money.parse(a.currency, '5'),
              expectedCategoryVersion: 1,
            ),
          ],
        );
        await source.post(
          classified,
          tags: [TagSelection(tag, 1)],
          merchant: MerchantSelection(merchant, 1),
        );
        await source.renameCategory(
          _operation(source),
          (await source.categories()).get(child),
          'Weekly groceries',
        );
        await source.renameTag(
          _operation(source),
          (await source.tags()).get(tag),
          'Daily essential',
        );
        await source.changeMerchantAlias(
          _operation(source),
          (await source.merchants()).get(merchant),
          'CARD MARKET',
          remove: false,
        );

        final original = Posting.expense(
          id: PublicId.generate(),
          operation: _operation(source),
          date: BusinessDate(2026, 9, 29),
          account: ref(a),
          amount: Money.parse(a.currency, '10'),
        );
        await source.post(original);
        final replacement = await source.saveEntryDraft(
          EntryFields(
            income: false,
            amount: '7',
            date: '2026-09-29',
            accountId: a.id,
            correctionOf: original.id,
            correctionReason: 'wrong amount',
          ),
        );
        await source.submitEntryDraft();
        await source.saveEntryDraft(
          EntryFields(
            income: false,
            amount: '',
            date: '',
            noteOf: replacement.id,
            noteRevision: 0,
            noteText: 'corrected receipt',
          ),
        );
        await source.submitEntryDraft();

        final removed = income(a);
        await source.post(removed);
        final deletion = PostingTombstone(
          original: removed,
          operation: _operation(source),
          reason: 'duplicate',
        );
        await source.tombstone(deletion);
        final externalAccount = PublicId.generate();
        final imported = SimpleTransactionBatch(
          WorkspaceId(PublicId.generate()),
          [
            SimpleTransaction(
              sourceRecordId: PublicId.generate(),
              date: BusinessDate(2026, 9, 29),
              kind: PostingKind.income,
              accountId: externalAccount,
              amount: Money.parse(a.currency, '1.25'),
              note: 'Imported once',
            ),
          ],
        );
        final mapping = {externalAccount: a.id};
        final importReview = await source.reviewSimpleImport(
          SimpleTransactionCodec.encodeJson(imported),
          csv: false,
          accountMapping: mapping,
        );
        final importResult = await source.confirmSimpleImport(importReview);
        expect(importResult.inserted, 1);
        expect(
          (await source.accounts()).single.balance,
          Money.parse(a.currency, '89.25'),
        );

        final backup = await source.exportBackup();
        final codec = EnvelopeCodec();
        final plain = await codec.openWithPassword(backup, password);
        final tables =
            (jsonDecode(utf8.decode(plain)) as Map<String, dynamic>)['tables']
                as Map<String, dynamic>;
        for (final name in [
          'categories',
          'tags',
          'merchants',
          'allocations',
          'event_tags',
          'event_merchants',
          'event_corrections',
          'event_note_revisions',
          'event_tombstones',
          'audit',
        ]) {
          expect(tables[name], isNotEmpty, reason: name);
        }
        await source.lock();
        final targetKey = await setup(target);
        await target.importBackup(
          backup,
          recovery ? sourceKey : password,
          recovery: recovery,
        );
        expect(
          (await target.accounts()).single.balance,
          Money.parse(a.currency, '89.25'),
        );
        expect(
          (await target.allocations(classified.id)).single.categoryVersion,
          1,
        );
        expect((await target.tagsFor(classified.id)).single.version, 1);
        expect((await target.merchantFor(classified.id))!.version, 1);
        expect((await target.categories()).get(child).name, 'Weekly groceries');
        expect((await target.tags()).get(tag).name, 'Daily essential');
        expect(
          (await target.merchants()).get(merchant).aliases,
          contains('CARD MARKET'),
        );
        expect(
          (await target.entryNote(replacement.id)).text,
          'corrected receipt',
        );
        expect(
          (await target.activity(removed.id))
              .where((row) => row.auditKind == 'ledger.tombstone'),
          hasLength(1),
        );
        expect(
          await codec.openWithRecovery(await target.exportBackup(), targetKey),
          plain,
        );
        await target.post(
          classified,
          tags: [TagSelection(tag, 1)],
          merchant: MerchantSelection(merchant, 1),
        );
        await target.tombstone(deletion);
        final replayReview = await target.reviewSimpleImport(
          SimpleTransactionCodec.encodeCsv(imported),
          csv: true,
          accountMapping: mapping,
        );
        final replay = await target.confirmSimpleImport(replayReview);
        expect(replay.inserted, 0);
        expect(replay.replayed, 1);
        expect(replay.entryIds, importResult.entryIds);
        expect(
          (await target.entryNote(importResult.entryIds.single)).text,
          'Imported once',
        );
        expect(
          await codec.openWithPassword(await target.exportBackup(), password),
          plain,
        );
        expect(await target.hasSafetyCopy(), isTrue);
      } finally {
        await source.lock();
        await target.lock();
        deleteSynthetic(sourceDir, root);
        deleteSynthetic(targetDir, root);
      }
    });
  }
}
