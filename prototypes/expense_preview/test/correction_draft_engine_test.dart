import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';

import 'support.dart';

void main() {
  final root = Directory('.dart_tool/correction-draft-engine-tests')
    ..createSync(recursive: true);
  late Directory work;
  late MemoryVault vault;
  late PreviewEngine engine;
  String? stop;

  PreviewEngine open() => engineAt(
    work,
    vault,
    schemaVersion: 13,
    draftCheckpoint: (point) {
      if (point == stop) throw StateError('injected');
    },
  );

  setUp(() async {
    work = root.createTempSync('case-');
    vault = MemoryVault();
    stop = null;
    engine = open();
    await setup(engine);
  });
  tearDown(() async {
    await engine.lock();
    deleteSynthetic(work, root);
  });

  test(
    'encrypted correction draft freezes two operations and reconciles once',
    () async {
      final a = account(engine);
      await engine.createAccount(a, opening(a));
      final original = Posting.expense(
        id: PublicId.generate(),
        operation: OperationKey(
          engine.workspace,
          OperationId(PublicId.generate()),
        ),
        date: BusinessDate(2026, 9, 28),
        account: ref(a),
        amount: Money.parse(a.currency, '10'),
      );
      await engine.post(original);
      final draft = await engine.saveEntryDraft(
        EntryFields(
          income: false,
          amount: '7',
          date: '2026-10-01',
          accountId: a.id,
          correctionOf: original.id,
          correctionReason: '金額輸入錯誤',
        ),
      );
      await engine.lock();
      engine = open();
      await engine.unlock(password);
      expect((await engine.entryDraft())!.encode(), draft.encode());
      expect(
        (await engine.accounts()).single.balance,
        Money.parse(a.currency, '90'),
      );
      await expectLater(
        engine.exportBackup(),
        throwsA(isA<DraftNeedsResolution>()),
      );

      stop = 'draft-prepared';
      await expectLater(engine.submitEntryDraft(), throwsStateError);
      final frozen = (await engine.entryDraft())!;
      expect(frozen.correctionSubmission, isNotNull);
      expect(
        (await engine.accounts()).single.balance,
        Money.parse(a.currency, '90'),
      );
      await engine.lock();
      engine = open();
      await engine.unlock(password);
      expect((await engine.entryDraft())!.encode(), frozen.encode());

      stop = 'draft-committed';
      await expectLater(engine.submitEntryDraft(), throwsStateError);
      expect(await engine.entryDraft(), null);
      expect(
        (await engine.accounts()).single.balance,
        Money.parse(a.currency, '93'),
      );
      expect(await engine.entries(), hasLength(4));
      final history = await engine.activity(original.id);
      expect(history.map((row) => row.entry.id).toSet(), {
        original.id,
        frozen.correctionSubmission!.pair.reversal.id,
        frozen.id,
      });
      expect(
        history.singleWhere((row) => row.entry.id == frozen.id).correctionRole,
        CorrectionActivityRole.replacement,
      );
      stop = null;
      expect(await engine.exportBackup(), isNotEmpty);
      await engine.lock();
      engine = open();
      await engine.unlock(password);
      expect(await engine.entryDraft(), null);
      expect(
        (await engine.accounts()).single.balance,
        Money.parse(a.currency, '93'),
      );
    },
  );

  test(
    'FX transfer correction keeps both principals and fee independent',
    () async {
      final usd = Currency('USD', 2), jpy = Currency('JPY', 0);
      Account make(String name, Currency currency) => Account.open(
        id: PublicId.generate(),
        workspace: engine.workspace,
        name: name,
        kind: AccountKind.bank,
        currency: currency,
        openedOn: BusinessDate(2026, 9, 1),
      );
      final a = make('source', usd), b = make('destination', jpy);
      await engine.createAccount(
        a,
        Posting.opening(
          id: PublicId.generate(),
          operation: OperationKey(
            engine.workspace,
            OperationId(PublicId.generate()),
          ),
          date: a.openedOn,
          account: ref(a),
          amount: Money.parse(usd, '100'),
        ),
      );
      await engine.createAccount(
        b,
        Posting.opening(
          id: PublicId.generate(),
          operation: OperationKey(
            engine.workspace,
            OperationId(PublicId.generate()),
          ),
          date: b.openedOn,
          account: ref(b),
          amount: Money.parse(jpy, '100'),
        ),
      );
      final original = Posting.transfer(
        id: PublicId.generate(),
        operation: OperationKey(
          engine.workspace,
          OperationId(PublicId.generate()),
        ),
        date: BusinessDate(2026, 9, 28),
        source: ref(a),
        destination: ref(b),
        principal: Money.parse(usd, '10'),
        received: Money.parse(jpy, '1500'),
        fee: Money.parse(usd, '0.10'),
      );
      await engine.post(original);
      await engine.saveEntryDraft(
        EntryFields(
          income: false,
          transfer: true,
          correctionOf: original.id,
          amount: '7',
          date: '2026-10-01',
          accountId: a.id,
          destinationId: b.id,
          fee: '0.05',
          received: '1050',
        ),
      );
      await engine.submitEntryDraft();
      final balances = {
        for (final row in await engine.accounts()) row.account.id: row.balance,
      };
      expect(balances[a.id], Money.parse(usd, '92.95'));
      expect(balances[b.id], Money.parse(jpy, '1150'));
      expect(await engine.entries(), hasLength(5));
      expect(await engine.entryDraft(), null);
      expect(await engine.exportBackup(), isNotEmpty);
    },
  );
}
