import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:backup_envelope_probe/envelope.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';

import 'support.dart';

void main() {
  test('civil dates retain exact text through draft rejection, restart, retry and independent restores', () async {
    final root = Directory('.dart_tool/date-engine')
      ..createSync(recursive: true);
    final work = root.createTempSync('source-');
    final vault = MemoryVault();
    var interrupt = false;
    PreviewEngine create() => engineAt(
      work,
      vault,
      schemaVersion: 7,
      draftCheckpoint: (point) {
        if (interrupt && point == 'draft-committed') {
          interrupt = false;
          throw StateError('injected');
        }
      },
    );
    var engine = create();
    try {
      final recovery = await setup(engine);
      final a = Account.open(
        id: PublicId.generate(),
        workspace: engine.workspace,
        name: '日期現金',
        kind: AccountKind.cash,
        currency: Currency('TWD', 2),
        openedOn: BusinessDate(1, 1, 1),
      );
      final initial = opening(a);
      await engine.createAccount(a, initial);
      EntryFields fields(String date) =>
          EntryFields(income: false, accountId: a.id, amount: '1', date: date);
      final first = await engine.saveEntryDraft(fields('2023-02-29'));
      await engine.lock();
      engine = create();
      await engine.unlock(password);
      expect((await engine.entryDraft())!.fields.date, '2023-02-29');
      await expectLater(engine.submitEntryDraft(), throwsFormatException);
      expect(await engine.entries(), hasLength(1));
      expect(
        (await engine.accounts()).single.balance.minorUnits,
        BigInt.from(10000),
      );

      final expected = <PublicId, String>{initial.id: '0001-01-01'};
      for (final date in ['2024-02-29', '2011-12-30', '9999-12-31']) {
        final saved = await engine.saveEntryDraft(fields(date));
        if (date == '2024-02-29') {
          expect(saved.id, first.id);
          expect(saved.operation, first.operation);
          interrupt = true;
          await expectLater(engine.submitEntryDraft(), throwsStateError);
          await engine.lock();
          engine = create();
          await engine.unlock(password);
          expect(await engine.entryDraft(), isNull);
        } else {
          await engine.submitEntryDraft();
        }
        expected[saved.id] = date;
      }
      Future<void> verify(PreviewEngine target) async {
        final rows = await target.entries();
        expect({for (final row in rows) row.id: row.date.toString()}, expected);
        expect(
          (await target.accounts()).single.account.openedOn.toString(),
          '0001-01-01',
        );
        expect(
          (await target.accounts()).single.balance.minorUnits,
          BigInt.from(9700),
        );
      }

      await verify(engine);
      final backup = await engine.exportBackup();
      final snapshot = await EnvelopeCodec().openWithPassword(backup, password);
      await engine.lock();
      vault.values.clear();
      deleteSynthetic(work, root);
      for (final useRecovery in [false, true]) {
        final clean = root.createTempSync('restore-');
        final target = engineAt(clean, MemoryVault(), schemaVersion: 7);
        try {
          await setup(target);
          await target.importBackup(
            backup,
            useRecovery ? recovery : password,
            recovery: useRecovery,
          );
          await verify(target);
          await target.lock();
          await target.unlock(password);
          await verify(target);
          expect(
            await EnvelopeCodec().openWithPassword(
              await target.exportBackup(),
              password,
            ),
            snapshot,
          );
        } finally {
          await target.lock();
          deleteSynthetic(clean, root);
        }
      }
    } finally {
      await engine.lock();
      if (work.existsSync()) deleteSynthetic(work, root);
    }
  });
}
