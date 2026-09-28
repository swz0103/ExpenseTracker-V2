import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';

void main() {
  final root = Directory('.dart_tool/correction-backup-gate')
    ..createSync(recursive: true);

  for (final recovery in [false, true]) {
    test(
      'clean ${recovery ? 'recovery' : 'password'} restore preserves correction and note revision',
      () async {
        final sourceDir = root.createTempSync('source-');
        final targetDir = root.createTempSync('target-');
        final source = engineAt(sourceDir, MemoryVault(), schemaVersion: 14);
        final target = engineAt(targetDir, MemoryVault(), schemaVersion: 14);
        try {
          final sourceKey = await setup(source);
          final a = account(source);
          await source.createAccount(a, opening(a));
          final original = Posting.expense(
            id: PublicId.generate(),
            operation: OperationKey(
              source.workspace,
              OperationId(PublicId.generate()),
            ),
            date: BusinessDate(2026, 9, 28),
            account: ref(a),
            amount: Money.parse(a.currency, '10'),
          );
          await source.post(original);
          final replacement = await source.saveEntryDraft(
            EntryFields(
              income: false,
              amount: '7',
              date: '2026-10-01',
              accountId: a.id,
              correctionOf: original.id,
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
          expect(
            (await source.accounts()).single.balance,
            Money.parse(a.currency, '93'),
          );
          final backup = await source.exportBackup();
          final codec = EnvelopeCodec();
          final plain = await codec.openWithPassword(backup, password);
          final tables =
              (jsonDecode(utf8.decode(plain)) as Map<String, dynamic>)['tables']
                  as Map<String, dynamic>;
          expect(tables['event_corrections'], hasLength(1));
          expect(tables['event_note_revisions'], hasLength(1));
          final auditBefore = (tables['audit'] as List).length;
          await source.lock();

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
          expect(
            (await target.entryNote(replacement.id)).text,
            'corrected receipt',
          );
          expect((await target.entryNote(replacement.id)).revision, 1);
          final history = await target.activity(original.id);
          expect(
            history.where((row) => row.correctionRole != null),
            isNotEmpty,
          );
          final restoredBackup = await target.exportBackup();
          expect(
            await codec.openWithRecovery(restoredBackup, targetKey),
            plain,
          );
          final restoredTables =
              (jsonDecode(
                    utf8.decode(
                      await codec.openWithPassword(restoredBackup, password),
                    ),
                  ) as Map<String, dynamic>)['tables']
                  as Map<String, dynamic>;
          expect((restoredTables['audit'] as List).length, auditBefore);
          expect(await target.hasSafetyCopy(), isTrue);
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
