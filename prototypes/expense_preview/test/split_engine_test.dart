import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:backup_envelope_probe/envelope.dart';
import 'package:categories/categories.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';

void main() {
  final root = Directory('.dart_tool/split-engine-tests')
    ..createSync(recursive: true);
  late Directory work;
  late MemoryVault vault;
  late PreviewEngine engine;
  late Account a;
  late List<PublicId> categories;
  late String recovery;
  String? stop;
  OperationKey op() =>
      OperationKey(engine.workspace, OperationId(PublicId.generate()));
  EntryFields fields({
    String amount = '10',
    List<SplitFields>? rows,
    bool income = false,
  }) => EntryFields(
    income: income,
    split: true,
    accountId: a.id,
    amount: amount,
    date: '2026-09-28',
    splits:
        rows ??
        [
          SplitFields(categoryId: categories[0], amount: '3.25'),
          SplitFields(categoryId: categories[1], amount: '6.75'),
        ],
  );
  setUp(() async {
    work = root.createTempSync('case-');
    vault = MemoryVault();
    stop = null;
    engine = engineAt(
      Directory('${work.path}/app'),
      vault,
      schemaVersion: 9,
      draftCheckpoint: (p) {
        if (p == stop) throw StateError('injected-$p');
      },
    );
    recovery = await setup(engine);
    a = account(engine);
    await engine.createAccount(a, opening(a));
    categories = [PublicId.generate(), PublicId.generate()];
    for (var i = 0; i < 2; i++) {
      await engine.createCategory(
        op(),
        categories[i],
        '分類 $i',
        CategoryKind.expense,
      );
    }
  });
  tearDown(() async {
    await engine.lock();
    deleteSynthetic(work, root);
  });
  test('partial raw rows survive restart; invalid sum, duplicates, missing, precision, zero and kind leave ledger unchanged', () async {
    final d = await engine.saveEntryDraft(
      fields(
        rows: [
          SplitFields(categoryId: categories[0], amount: '1+'),
          SplitFields(amount: ''),
        ],
      ),
    );
    await engine.lock();
    engine = engineAt(Directory('${work.path}/app'), vault, schemaVersion: 9);
    await engine.unlock(password);
    expect((await engine.entryDraft())!.encode(), d.encode());
    for (final invalid in [
      fields(amount: '11'),
      fields(income: true),
      fields(rows: []),
      fields(
        rows: [SplitFields(categoryId: categories[0], amount: '10')],
      ),
      fields(
        rows: [
          SplitFields(categoryId: categories[0], amount: '3.25'),
          SplitFields(categoryId: categories[0], amount: '6.75'),
        ],
      ),
      for (final amount in [
        '',
        '0',
        '-1',
        '3.251',
        '1+2',
        '92233720368547758.08',
      ])
        fields(
          rows: [
            SplitFields(categoryId: categories[0], amount: amount),
            SplitFields(categoryId: categories[1], amount: '6.75'),
          ],
        ),
      fields(
        rows: [
          SplitFields(amount: '3.25'),
          SplitFields(categoryId: categories[1], amount: '6.75'),
        ],
      ),
    ]) {
      await engine.saveEntryDraft(invalid);
      await expectLater(engine.submitEntryDraft(), throwsA(anything));
      expect((await engine.entryDraft())!.submission, null);
      expect((await engine.entries()).length, 1);
      expect(
        (await engine.accounts()).single.balance.minorUnits,
        BigInt.from(10000),
      );
    }
    await engine.saveEntryDraft(fields());
    await engine.submitEntryDraft();
    expect(
      (await engine.accounts()).single.balance.minorUnits,
      BigInt.from(9000),
    );
    final splits = await engine.allocations(d.id);
    expect(splits.map((s) => s.amount.minorUnits.toInt()).toSet(), {325, 675});
  });
  test('prepared command keeps versions; conflict requires explicit edit; committed retry survives category changes', () async {
    final d = await engine.saveEntryDraft(fields());
    stop = 'draft-prepared';
    await expectLater(engine.submitEntryDraft(), throwsStateError);
    await engine.renameCategory(
      op(),
      (await engine.categories()).get(categories[1]),
      '新名稱',
    );
    stop = null;
    await expectLater(
      engine.submitEntryDraft(),
      throwsA(isA<CategoryException>()),
    );
    expect((await engine.entries()).length, 1);
    expect(
      (await engine.entryDraft())!
          .submission!
          .posting
          .allocations[1]
          .expectedCategoryVersion,
      1,
    );
    await expectLater(
      engine.saveEntryDraft(fields()),
      throwsA(isA<DraftNeedsResolution>()),
    );
    await engine.reopenEntryDraft();
    await engine.saveEntryDraft(fields());
    stop = 'draft-committed';
    await expectLater(engine.submitEntryDraft(), throwsStateError);
    await engine.archiveCategory(
      op(),
      (await engine.categories()).get(categories[0]),
      archived: true,
    );
    stop = null;
    expect(await engine.entryDraft(), null);
    final rows = await engine.allocations(d.id);
    expect(
      rows.firstWhere((s) => s.categoryId == categories[1]).categoryVersion,
      2,
    );
    expect(
      rows.firstWhere((s) => s.categoryId == categories[0]).categoryVersion,
      1,
    );
    expect((await engine.entries()).length, 2);
  });
  test('copy preserves split structure with blank amounts and unavailable category placeholders', () async {
    final d = await engine.saveEntryDraft(fields());
    await engine.submitEntryDraft();
    await engine.archiveCategory(
      op(),
      (await engine.categories()).get(categories[0]),
      archived: true,
    );
    final copy = await engine.preparePostingCopy(d.id);
    expect(copy.categoryId, null);
    expect(copy.splitCategories.toSet(), {null, categories[1]});
    expect(copy.omittedMetadata, true);
    expect((await engine.entries()).length, 2);
    expect(() => copy.splitCategories.clear(), throwsUnsupportedError);
  });
  test('split pending draft blocks backup; committed split restores exactly through both credentials with fresh keys', () async {
    final d = await engine.saveEntryDraft(fields());
    await expectLater(
      engine.exportBackup(),
      throwsA(isA<DraftNeedsResolution>()),
    );
    await engine.submitEntryDraft();
    final backup = await engine.exportBackup();
    final expected = await EnvelopeCodec().openWithPassword(backup, password);
    await engine.lock();
    deleteSynthetic(Directory('${work.path}/app'), work);
    vault.values.clear();
    for (final rescue in [false, true]) {
      final restored = engineAt(
        Directory('${work.path}/restored-$rescue'),
        MemoryVault(),
        schemaVersion: 9,
      );
      try {
        await setup(restored);
        await restored.importBackup(
          backup,
          rescue ? recovery : password,
          recovery: rescue,
        );
        expect(
          await EnvelopeCodec().openWithPassword(
            await restored.exportBackup(),
            password,
          ),
          expected,
        );
        final rows = await restored.allocations(d.id);
        expect(rows.map((s) => s.amount.minorUnits.toInt()).toSet(), {
          325,
          675,
        });
        expect(
          (await restored.accounts()).single.balance.minorUnits,
          BigInt.from(9000),
        );
      } finally {
        await restored.lock();
      }
    }
  });
  test('sixteen income allocations admit exact maximum principal and preserve one ledger leg', () async {
    final ids = List.generate(16, (_) => PublicId.generate());
    for (var i = 0; i < ids.length; i++) {
      await engine.createCategory(op(), ids[i], '收入 $i', CategoryKind.income);
    }
    // A zero opening avoids balance overflow while testing the maximum command.
    a = account(engine);
    final original = opening(a);
    await engine.createAccount(
      a,
      Posting.opening(
        id: original.id,
        operation: original.operation,
        date: a.openedOn,
        account: ref(a),
        amount: Money(a.currency, BigInt.zero),
      ),
    );
    final d = await engine.saveEntryDraft(
      fields(
        income: true,
        amount: '92233720368547758.07',
        rows: [
          SplitFields(categoryId: ids[0], amount: '92233720368547757.92'),
          for (final id in ids.skip(1))
            SplitFields(categoryId: id, amount: '0.01'),
        ],
      ),
    );
    await engine.submitEntryDraft();
    expect((await engine.allocations(d.id)).length, 16);
    final backup = await engine.exportBackup();
    await engine.importBackup(backup, password, recovery: false);
    expect((await engine.allocations(d.id)).length, 16);
    expect(
      (await engine.accounts())
          .firstWhere((s) => s.account.id == a.id)
          .balance
          .minorUnits,
      Money.maxMinorUnits,
    );
  });
}
