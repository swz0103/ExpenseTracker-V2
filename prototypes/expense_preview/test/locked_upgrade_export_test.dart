import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:expense_preview/main.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, settle, tap, input, closeEngine;

int schemaOf(List<int> bytes) =>
    (jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>)['schema'] as int;

void main() {
  final root = Directory('.dart_tool/locked-upgrade-export')
    ..createSync(recursive: true);

  test('locked export verifies both credentials and falls back from a partial upgrade backup', () async {
    final work = root.createTempSync('engine-');
    final vault = MemoryVault();
    var engine = engineAt(work, vault, schemaVersion: 12);
    try {
      final key = await setup(engine);
      final a = account(engine);
      await engine.createAccount(a, opening(a));
      await engine.post(income(a));
      await engine.lock();
      engine = engineAt(work, vault, schemaVersion: 14);
      await engine.upgrade(password);
      final current = await engine.exportBackup();
      await engine.lock();
      expect(await engine.hasLockedUpgradeCopy(), isTrue);
      await expectLater(
        engine.exportLockedUpgradeCopy('wrong-password', recovery: false),
        throwsA(isA<PreviewInvalid>()),
      );
      for (final recovery in [false, true]) {
        final saved = await engine.exportLockedUpgradeCopy(
          recovery ? key : password,
          recovery: recovery,
        );
        expect(
          schemaOf(await EnvelopeCodec().openWithPassword(saved, password)),
          13,
        );
      }
      final folder = Directory('${work.path}/upgrade-backups');
      final copies = folder.listSync().whereType<File>().toList();
      expect(copies, hasLength(2));
      final misleading = File(
        '${folder.path}/${PublicId.generate().value}.envelope',
      )..writeAsStringSync(current, flush: true);
      misleading.setLastModifiedSync(DateTime.utc(2100));
      expect(
        schemaOf(
          await EnvelopeCodec().openWithPassword(
            await engine.exportLockedUpgradeCopy(password, recovery: false),
            password,
          ),
        ),
        13,
      );
      for (final file in copies) {
        final plain = await EnvelopeCodec().openWithPassword(
          await file.readAsString(),
          password,
        );
        if (schemaOf(plain) == 13) {
          file.writeAsStringSync('partial', flush: true);
        }
      }
      final fallback = await engine.exportLockedUpgradeCopy(
        key,
        recovery: true,
      );
      expect(
        schemaOf(await EnvelopeCodec().openWithPassword(fallback, password)),
        12,
      );
      await engine.unlock(password);
      expect(
        (await engine.accounts()).single.balance,
        Money.parse(a.currency, '107'),
      );
    } finally {
      await engine.lock();
      deleteSynthetic(work, root);
    }
  });

  for (final recovery in [false, true]) {
    testWidgets(
      'blocked profile can save ${recovery ? 'recovery' : 'password'} verified upgrade backup',
      (tester) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final work = root.createTempSync('widget-');
        final vault = MemoryVault();
        var engine = engineAt(work, vault, schemaVersion: 12);
        final documents = Documents();
        try {
          late String key;
          await tester.runAsync(() async {
            key = await setup(engine);
            final a = account(engine);
            await engine.createAccount(a, opening(a));
            await engine.lock();
            engine = engineAt(work, vault, schemaVersion: 14);
            await engine.upgrade(password);
            await engine.lock();
            File('${work.path}/profile.pending').writeAsStringSync('damaged');
          });
          await tester.pumpWidget(
            PreviewApp(engine: Future.value(engine), documents: documents),
          );
          await settle(tester);
          expect(find.text('匯出升級前加密備份'), findsOneWidget);
          if (recovery) {
            await tester.tap(find.widgetWithText(SwitchListTile, '使用救援文字'));
            await tester.pumpAndSettle();
          }
          await input(
            tester,
            recovery ? '原帳本救援文字' : '原帳本密碼',
            recovery ? key : password,
          );
          await tap(tester, '匯出升級前加密備份');
          await tester.runAsync(() async {
            expect(
              schemaOf(
                await EnvelopeCodec().openWithPassword(
                  documents.saved!,
                  password,
                ),
              ),
              13,
            );
            expect(File('${work.path}/profile.pending').existsSync(), isTrue);
            expect(engine.isUnlocked, isFalse);
          });
          expect(tester.takeException(), isNull);
        } finally {
          await closeEngine(tester, engine);
          await tester.pumpWidget(const SizedBox());
          deleteSynthetic(work, root);
        }
      },
    );
  }
}
