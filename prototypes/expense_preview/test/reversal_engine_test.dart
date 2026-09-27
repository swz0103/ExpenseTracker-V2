import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:categories/categories.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';

void main() {
  final root = Directory('.dart_tool/reversal-engine-tests')
    ..createSync(recursive: true);
  late Directory work;
  late MemoryVault vault;
  late PreviewEngine engine;
  late Account a, b;
  late PublicId food, travel;
  late Posting original;
  String? stop;
  OperationKey op() =>
      OperationKey(engine.workspace, OperationId(PublicId.generate()));
  EntryFields fields({String date = '2026-09-28', String reason = '輸入錯誤'}) =>
      EntryFields(
        income: false,
        amount: '',
        date: date,
        reversalOf: original.id,
        reversalReason: reason,
      );
  setUp(() async {
    work = root.createTempSync('case-');
    vault = MemoryVault();
    stop = null;
    engine = engineAt(
      work,
      vault,
      schemaVersion: 11,
      draftCheckpoint: (p) {
        if (p == stop) throw StateError('injected');
      },
    );
    await setup(engine);
    a = account(engine);
    b = Account.open(
      id: PublicId.generate(),
      workspace: engine.workspace,
      name: 'JPY',
      kind: AccountKind.bank,
      currency: Currency('JPY', 0),
      openedOn: a.openedOn,
    );
    await engine.createAccount(a, opening(a));
    await engine.createAccount(b, opening(b));
    food = PublicId.generate();
    travel = PublicId.generate();
    await engine.createCategory(op(), food, 'food', CategoryKind.expense);
    await engine.createCategory(op(), travel, 'travel', CategoryKind.expense);
    original = Posting.expense(
      id: PublicId.generate(),
      operation: op(),
      date: BusinessDate(2026, 9, 27),
      account: ref(a),
      amount: Money.parse(a.currency, '10'),
      allocations: [
        Allocation(
          food,
          Money.parse(a.currency, '6'),
          expectedCategoryVersion: 1,
        ),
        Allocation(
          travel,
          Money.parse(a.currency, '4'),
          expectedCategoryVersion: 1,
        ),
      ],
    );
    await engine.post(original);
  });
  tearDown(() async {
    await engine.lock();
    deleteSynthetic(work, root);
  });

  test(
    'raw reversal survives restart, invalid date leaves ledger intact',
    () async {
      final saved = await engine.saveEntryDraft(fields(date: '2026-'));
      await engine.lock();
      engine = engineAt(work, vault, schemaVersion: 11);
      await engine.unlock(password);
      expect((await engine.entryDraft())!.encode(), saved.encode());
      for (final date in ['2026-', '2026-09-26']) {
        await engine.saveEntryDraft(fields(date: date));
        await expectLater(engine.submitEntryDraft(), throwsA(anything));
        expect(await engine.entries(), hasLength(3));
      }
      await engine.saveEntryDraft(fields());
      await engine.submitEntryDraft();
      expect(await engine.entryDraft(), null);
      final entries = await engine.entries();
      expect(entries, hasLength(4));
      final r = entries.singleWhere((e) => e.kind == PostingKind.reversal);
      expect(r.reversalOf, original.id);
      expect(
        (await engine.accounts())
            .singleWhere((r) => r.account.id == a.id)
            .balance,
        Money.parse(a.currency, '100'),
      );
      final backup = await engine.exportBackup();
      expect(backup, isNotEmpty);
    },
  );
  test('frozen reversal after prepare and commit failure replays once despite archived metadata', () async {
    final d = await engine.saveEntryDraft(fields());
    stop = 'draft-prepared';
    await expectLater(engine.submitEntryDraft(), throwsStateError);
    await expectLater(
      engine.exportBackup(),
      throwsA(isA<DraftNeedsResolution>()),
    );
    await engine.archiveCategory(
      op(),
      (await engine.categories()).get(food),
      archived: true,
    );
    stop = 'draft-committed';
    await expectLater(engine.submitEntryDraft(), throwsStateError);
    stop = null;
    expect(await engine.entryDraft(), null);
    expect(await engine.entries(), hasLength(4));
    expect((await engine.allocations(d.id)), hasLength(2));
    final activity = await engine.activity(d.id);
    expect(activity.map((r) => r.entry.id).toSet(), {d.id, original.id});
    await engine.exportBackup();
  });
  test('uncommitted frozen reversal can reopen without changing operation and cannot add arbitrary amount', () async {
    final d = await engine.saveEntryDraft(fields());
    stop = 'draft-prepared';
    await expectLater(engine.submitEntryDraft(), throwsStateError);
    await expectLater(
      engine.saveEntryDraft(fields()),
      throwsA(isA<DraftNeedsResolution>()),
    );
    await engine.reopenEntryDraft();
    stop = null;
    final edited = await engine.saveEntryDraft(fields(reason: '核對後撤銷'));
    expect(edited.operation.operation, d.operation.operation);
    await engine.submitEntryDraft();
    expect(
      (await engine.entries()).singleWhere((e) => e.id == d.id).reversalReason,
      '核對後撤銷',
    );
  });
}
