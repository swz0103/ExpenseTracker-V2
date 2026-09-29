import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:backup_envelope_probe/envelope.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:storage_generation_probe/generation_store.dart';

import 'support.dart';

void main() {
  final root = Directory('.dart_tool/card-upgrade-tests')
    ..createSync(recursive: true);
  late Directory work;
  late MemoryVault vault;
  late PreviewEngine engine;

  setUp(() {
    work = root.createTempSync('case-');
    vault = MemoryVault();
    engine = engineAt(work, vault, schemaVersion: 16);
  });
  tearDown(() async {
    await engine.lock();
    deleteSynthetic(work, root);
  });

  test(
    'schema 16 to 17 safely resumes and restores card settings both ways',
    () async {
      final recoveryKey = await setup(engine);
      final cash = account(engine);
      await engine.createAccount(cash, opening(cash));
      final prior = await engine.accounts();
      await engine.lock();

      engine = engineAt(
        work,
        vault,
        schemaVersion: 17,
        checkpoint: (point) {
          if (point == '16:table:card_revisions') throw StateError('injected');
        },
      );
      await expectLater(
        engine.unlock(password),
        throwsA(isA<PreviewUpgradeRequired>()),
      );
      await expectLater(
        engine.upgrade(password),
        throwsA(isA<GenerationUnavailable>()),
      );
      await engine.lock();
      engine = engineAt(work, vault, schemaVersion: 16);
      await engine.unlock(password);
      expect((await engine.accounts()).single.balance, prior.single.balance);
      await engine.lock();

      engine = engineAt(work, vault, schemaVersion: 17);
      await engine.upgrade(password);
      expect(engine.capabilities.creditCards, isTrue);
      expect(await engine.savedCreditCards(), isEmpty);
      final card = Account.open(
        id: PublicId.generate(),
        workspace: engine.workspace,
        name: 'Synthetic card',
        kind: AccountKind.creditCard,
        currency: Currency('TWD', 2),
        openedOn: BusinessDate(2026, 9, 29),
      );
      final terms = CreditCardTerms(
        workspace: engine.workspace,
        cardId: card.id,
        currency: card.currency,
        closingDay: 30,
        dueDay: 15,
      );
      await engine.createAccount(
        card,
        Posting.opening(
          id: PublicId.generate(),
          operation: OperationKey(
            engine.workspace,
            OperationId(PublicId.generate()),
          ),
          date: card.openedOn,
          account: ref(card),
          amount: Money(card.currency, BigInt.zero),
        ),
        cardTerms: terms,
      );
      expect((await engine.savedCreditCards()).single.closingDay, 30);
      final revision = CreditCardTerms(
        workspace: terms.workspace,
        cardId: terms.cardId,
        currency: terms.currency,
        closingDay: 28,
        dueDay: 15,
        version: 2,
      );
      await engine.reviseCreditCard(revision, OperationId(PublicId.generate()));
      expect((await engine.savedCreditCards()).single.closingDay, 28);
      final backup = await engine.exportBackup();
      final plain = await EnvelopeCodec().openWithPassword(backup, password);
      expect(jsonDecode(utf8.decode(plain))['schema'], 17);
      final upgradeBackups = Directory('${work.path}/upgrade-backups')
          .listSync()
          .whereType<File>()
          .toList();
      expect(upgradeBackups, isNotEmpty);
      final priorEnvelope = await upgradeBackups.last.readAsString();
      expect(
        jsonDecode(
          utf8.decode(
            await EnvelopeCodec().openWithPassword(priorEnvelope, password),
          ),
        )['schema'],
        16,
      );

      for (final useRecovery in [false, true]) {
        final targetDir = root.createTempSync('restore-');
        final target = engineAt(targetDir, MemoryVault(), schemaVersion: 17);
        try {
          await setup(target);
          await target.importBackup(
            backup,
            useRecovery ? recoveryKey : password,
            recovery: useRecovery,
          );
          expect((await target.savedCreditCards()).single.closingDay, 28);
          expect(await target.accounts(), hasLength(2));
        } finally {
          await target.lock();
          deleteSynthetic(targetDir, root);
        }
      }
    },
  );
}
