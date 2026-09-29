import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:expense_preview/main.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, settle, tap, input, closeEngine;

void main() {
  testWidgets(
    'V2 schema 12 opens current schema 15 only after explicit safety-backed upgrade',
    (tester) async {
      expect(currentPreviewSchemaVersion, 15);
      final root = Directory('.dart_tool/current-schema-upgrade-widget')
        ..createSync(recursive: true);
      final work = root.createTempSync('case-');
      final vault = MemoryVault();
      var engine = engineAt(work, vault, schemaVersion: 12);
      late PublicId expenseId;
      late String recoveryKey;
      late List<int> oldSnapshot;
      try {
        await tester.runAsync(() async {
          recoveryKey = await setup(engine);
          final a = account(engine);
          await engine.createAccount(a, opening(a));
          final expense = Posting.expense(
            id: PublicId.generate(),
            operation: OperationKey(
              engine.workspace,
              OperationId(PublicId.generate()),
            ),
            date: BusinessDate(2026, 9, 28),
            account: ref(a),
            amount: Money.parse(a.currency, '10'),
          );
          expenseId = expense.id;
          await engine.post(expense);
          await engine.saveEntryDraft(
            EntryFields(
              income: false,
              amount: '',
              date: '',
              noteOf: expense.id,
              noteRevision: 0,
              noteText: 'old V2 receipt',
            ),
          );
          await engine.submitEntryDraft();
          oldSnapshot = await EnvelopeCodec().openWithPassword(
            await engine.exportBackup(),
            password,
          );
          await engine.lock();
        });
        engine = engineAt(
          work,
          vault,
          schemaVersion: currentPreviewSchemaVersion,
        );
        await tester.pumpWidget(
          PreviewApp(engine: Future.value(engine), documents: Documents()),
        );
        await settle(tester);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        expect(find.text('更新帳本'), findsOneWidget);
        expect(engine.isUnlocked, isFalse);
        expect(Directory('${work.path}/upgrade-backups').existsSync(), isFalse);
        await tap(tester, '稍後再更新');
        expect(find.text('解鎖帳本'), findsOneWidget);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        await tap(tester, '備份並更新');
        expect(find.text('我的帳本'), findsOneWidget);
        expect(engine.capabilities.corrections, isTrue);
        expect(engine.capabilities.tombstones, isTrue);
        expect(engine.capabilities.budgets, isTrue);
        await tester.runAsync(() async {
          expect(
            (await engine.accounts()).single.balance,
            Money.parse(Currency('TWD', 2), '90'),
          );
          expect((await engine.entryNote(expenseId)).text, 'old V2 receipt');
          final copies = Directory('${work.path}/upgrade-backups')
              .listSync()
              .whereType<File>()
              .toList();
          expect(copies, hasLength(3));
          final schemas = <int>{};
          for (final copy in copies) {
            final encrypted = copy.readAsStringSync();
            final fromPassword = await EnvelopeCodec().openWithPassword(
              encrypted,
              password,
            );
            final fromRecovery = await EnvelopeCodec().openWithRecovery(
              encrypted,
              recoveryKey,
            );
            expect(fromRecovery, fromPassword);
            final schema =
                (jsonDecode(utf8.decode(fromPassword)) as Map)['schema'] as int;
            schemas.add(schema);
            if (schema == 12) expect(fromPassword, oldSnapshot);
          }
          expect(schemas, {12, 13, 14});
          expect(await engine.exportBackup(), isNotEmpty);
        });
        final actions = find.byKey(ValueKey('entry-actions-$expenseId'));
        await tester.scrollUntilVisible(
          actions,
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(actions);
        await tester.tap(actions);
        await tester.pumpAndSettle();
        expect(find.text('更正交易'), findsOneWidget);
        expect(find.text('刪除交易'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await closeEngine(tester, engine);
        await tester.pumpWidget(const SizedBox());
        deleteSynthetic(work, root);
      }
    },
  );
}
