import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:storage_generation_probe/generation_store.dart';

import 'support.dart';

void main() {
  final root = Directory('.dart_tool/multi-upgrade-backup-gate')
    ..createSync(recursive: true);

  for (final recovery in [false, true]) {
    test(
      'interrupted 12 to 14 upgrade resumes and ${recovery ? 'recovery' : 'password'} backup restores every authority',
      () async {
        final sourceDir = root.createTempSync('source-');
        final targetDir = root.createTempSync('target-');
        final vault = MemoryVault();
        var source = engineAt(sourceDir, vault, schemaVersion: 12);
        final target = engineAt(targetDir, MemoryVault(), schemaVersion: 14);
        try {
          final sourceKey = await setup(source);
          final a = account(source);
          await source.createAccount(a, opening(a));
          final expense = Posting.expense(
            id: PublicId.generate(),
            operation: OperationKey(
              source.workspace,
              OperationId(PublicId.generate()),
            ),
            date: BusinessDate(2026, 9, 28),
            account: ref(a),
            amount: Money.parse(a.currency, '10'),
          );
          await source.post(expense);
          await source.saveEntryDraft(
            EntryFields(
              income: false,
              amount: '',
              date: '',
              noteOf: expense.id,
              noteRevision: 0,
              noteText: 'original receipt',
            ),
          );
          await source.submitEntryDraft();
          await source.lock();

          // Schema 13 commits before this injected schema 14 failure. A retry
          // must resume from that committed generation, preserving the note.
          source = engineAt(
            sourceDir,
            vault,
            schemaVersion: 14,
            checkpoint: (point) {
              if (point == '13:table:event_tombstones') {
                throw StateError('injected');
              }
            },
          );
          await expectLater(
            source.upgrade(password),
            throwsA(isA<GenerationUnavailable>()),
          );
          await source.lock();
          source = engineAt(sourceDir, vault, schemaVersion: 13);
          await source.unlock(password);
          expect(
            (await source.accounts()).single.balance,
            Money.parse(a.currency, '90'),
          );
          expect((await source.entryNote(expense.id)).text, 'original receipt');
          expect(await source.exportBackup(), isNotEmpty);
          await source.lock();

          source = engineAt(sourceDir, vault, schemaVersion: 14);
          await source.upgrade(password);
          final replacement = await source.saveEntryDraft(
            EntryFields(
              income: false,
              amount: '7',
              date: '2026-10-01',
              accountId: a.id,
              correctionOf: expense.id,
              correctionReason: 'amount entered incorrectly',
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
            operation: OperationKey(
              source.workspace,
              OperationId(PublicId.generate()),
            ),
            reason: 'duplicate',
          );
          await source.tombstone(deletion);
          expect(
            (await source.accounts()).single.balance,
            Money.parse(a.currency, '93'),
          );

          final backup = await source.exportBackup();
          final plain = await EnvelopeCodec().openWithPassword(
            backup,
            password,
          );
          final snapshot =
              jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
          final tables = snapshot['tables'] as Map<String, dynamic>;
          expect(tables['event_note_revisions'], hasLength(2));
          expect(tables['event_corrections'], hasLength(1));
          expect(tables['event_tombstones'], hasLength(1));
          final targetKey = await setup(target);
          await target.importBackup(
            backup,
            recovery ? sourceKey : password,
            recovery: recovery,
          );
          expect(
            (await target.accounts()).single.balance,
            Money.parse(a.currency, '93'),
          );
          expect((await target.entryNote(expense.id)).text, 'original receipt');
          expect(
            (await target.entryNote(replacement.id)).text,
            'corrected receipt',
          );
          expect(
            (await target.activity(removed.id))
                .where((row) => row.auditKind == 'ledger.tombstone'),
            hasLength(1),
          );
          await target.tombstone(deletion);
          expect(
            (await target.accounts()).single.balance,
            Money.parse(a.currency, '93'),
          );
          final restored = await target.exportBackup();
          expect(
            await EnvelopeCodec().openWithRecovery(restored, targetKey),
            plain,
          );
        } finally {
          await source.lock();
          await target.lock();
          deleteSynthetic(sourceDir, root);
          deleteSynthetic(targetDir, root);
        }
      },
    );
  }
}
