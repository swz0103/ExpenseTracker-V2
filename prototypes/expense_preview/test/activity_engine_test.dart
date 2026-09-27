import 'dart:io';

import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';

void main() {
  final root = Directory('.dart_tool/activity-engine-tests')
    ..createSync(recursive: true);
  for (final recovery in [false, true]) {
    test(
      'activity preserves committed time after clean ${recovery ? 'recovery' : 'password'} restore and rejects locked reads',
      () async {
        final work = root.createTempSync('case-');
        final sourceDir = Directory('${work.path}/source');
        final sourceVault = MemoryVault();
        final source = engineAt(sourceDir, sourceVault, schemaVersion: 10);
        final target = engineAt(
          Directory('${work.path}/target'),
          MemoryVault(),
          schemaVersion: 10,
        );
        try {
          final key = await setup(source);
          final a = account(source);
          await source.createAccount(a, opening(a));
          final p = Posting.expense(
            id: PublicId.generate(),
            operation: OperationKey(
              source.workspace,
              OperationId(PublicId.generate()),
            ),
            date: BusinessDate(2026, 9, 1),
            account: ref(a),
            amount: Money.parse(a.currency, '50'),
          );
          await source.post(p);
          final r = Posting.refund(
            id: PublicId.generate(),
            operation: OperationKey(
              source.workspace,
              OperationId(PublicId.generate()),
            ),
            date: BusinessDate(2026, 9, 27),
            account: ref(a),
            originalId: p.id,
            amount: Money.parse(a.currency, '2'),
          );
          await source.post(r);
          await source.post(r);
          final rows = await source.activity(r.id);
          expect(rows.map((r) => r.entry.id), [r.id, p.id]);
          final expected = rows
              .map(
                (r) => [
                  r.entry.id.value,
                  r.recordedAt.toString(),
                  r.entry.amount.toJson(),
                ],
              )
              .toList();
          final backup = await source.exportBackup();
          await source.lock();
          await expectLater(
            source.activity(r.id),
            throwsA(isA<PreviewLocked>()),
          );
          deleteSynthetic(sourceDir, work);
          sourceVault.values.clear();
          await setup(target);
          await target.importBackup(
            backup,
            recovery ? key : password,
            recovery: recovery,
          );
          final after = await target.activity(p.id);
          expect(
            after
                .map(
                  (r) => [
                    r.entry.id.value,
                    r.recordedAt.toString(),
                    r.entry.amount.toJson(),
                  ],
                )
                .toList(),
            expected,
          );
          expect(
            (await target.accounts()).single.balance,
            Money.parse(a.currency, '52'),
          );
          await expectLater(
            target.activity(PublicId.generate()),
            throwsStateError,
          );
          expect((await target.activity(p.id)).length, 2);
        } finally {
          await source.lock();
          await target.lock();
          deleteSynthetic(work, root);
        }
      },
    );
  }
}
