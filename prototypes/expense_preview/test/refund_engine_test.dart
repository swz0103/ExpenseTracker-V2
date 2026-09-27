import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:categories/categories.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';

void main() {
  final root = Directory('.dart_tool/refund-engine-tests')
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
  EntryFields fields({
    String amount = '2',
    String first = '2',
    String second = '0',
    PublicId? target,
    String? received,
    String date = '2026-09-28',
  }) => EntryFields(
    income: false,
    refundOf: original.id,
    accountId: target ?? a.id,
    amount: amount,
    date: date,
    received: received,
    splits: [
      SplitFields(categoryId: food, amount: first),
      SplitFields(categoryId: travel, amount: second),
    ],
  );
  setUp(() async {
    work = root.createTempSync('case-');
    vault = MemoryVault();
    stop = null;
    engine = engineAt(
      work,
      vault,
      schemaVersion: 10,
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
  test('raw refund survives restart and invalid amount/date/category/FX leaves ledger intact', () async {
    final saved = await engine.saveEntryDraft(
      fields(amount: '2+', first: '2+'),
    );
    await engine.lock();
    engine = engineAt(work, vault, schemaVersion: 10);
    await engine.unlock(password);
    expect((await engine.entryDraft())!.encode(), saved.encode());
    for (final invalid in [
      fields(amount: '7', first: '7'),
      fields(amount: '0', first: '0'),
      fields(first: '-2'),
      fields(first: '2.001'),
      fields(second: '1'),
      fields(date: '2026-09-26'),
      fields(target: b.id),
      fields(received: '2'),
      fields(target: b.id, received: '0'),
    ]) {
      await engine.saveEntryDraft(invalid);
      await expectLater(engine.submitEntryDraft(), throwsA(anything));
      expect(await engine.entries(), hasLength(3));
    }
    // A structurally valid but financially invalid FX command may already be
    // frozen only after validation; all above fail before prepare.
    expect((await engine.entryDraft())!.submission, null);
    await engine.saveEntryDraft(fields());
    await engine.submitEntryDraft();
    expect(
      (await engine.refundStatus(original.id)).budget.remaining,
      Money.parse(a.currency, '8'),
    );
  });
  test('frozen partial refund inherits archived category and committed retry does not duplicate FX cash', () async {
    final d = await engine.saveEntryDraft(
      fields(target: b.id, received: '310'),
    );
    stop = 'draft-prepared';
    await expectLater(engine.submitEntryDraft(), throwsStateError);
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
    expect((await engine.allocations(d.id)).single.categoryVersion, 1);
    expect(
      (await engine.accounts())
          .singleWhere((r) => r.account.id == b.id)
          .balance,
      Money.parse(b.currency, '410'),
    );
    expect(
      (await engine.refundStatus(original.id)).budget.remaining,
      Money.parse(a.currency, '8'),
    );
  });
  test('pending refund blocks backup; explicit reopen preserves operation then subset completes original budget', () async {
    final d = await engine.saveEntryDraft(fields());
    await expectLater(
      engine.exportBackup(),
      throwsA(isA<DraftNeedsResolution>()),
    );
    stop = 'draft-prepared';
    await expectLater(engine.submitEntryDraft(), throwsStateError);
    await expectLater(
      engine.saveEntryDraft(fields()),
      throwsA(isA<DraftNeedsResolution>()),
    );
    await engine.reopenEntryDraft();
    stop = null;
    await engine.saveEntryDraft(fields(amount: '4', first: '0', second: '4'));
    await engine.submitEntryDraft();
    expect((await engine.entries()).any((e) => e.id == d.id), true);
    final next = await engine.saveEntryDraft(fields(amount: '6', first: '6'));
    await engine.submitEntryDraft();
    expect(
      (await engine.refundStatus(original.id)).budget.remaining.minorUnits,
      BigInt.zero,
    );
    expect((await engine.allocations(next.id)).single.categoryId, food);
    expect(
      (await engine.accounts())
          .singleWhere((r) => r.account.id == a.id)
          .balance,
      Money.parse(a.currency, '100'),
    );
    await engine.exportBackup();
  });
}
