import 'dart:math';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/persistence/unit_of_work.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keeps nothing: only remembers the batches it was handed.
final class _Batches implements LedgerDataSource {
  final kept = <WriteBatch>[];

  @override
  Future<void> keep(WriteBatch batch) async => kept.add(batch);

  @override
  Future<Ledger> load() => throw UnimplementedError();
}

Entry _entry(
  String id, {
  String category = '飲食',
  List<String> tags = const [],
}) => Entry(
  id: id,
  date: DateTime.utc(2026, 9, 1),
  type: EntryType.expense,
  amount: 100,
  account: 'bank',
  category: category,
  tags: tags,
);

/// A batch as comparable text: each record by key and which instance it
/// is, so the same record changed twice reads differently.
Set<String> _shape(WriteBatch b, Map<Object, int> ids) {
  String id(Object o) => '${ids.putIfAbsent(o, () => ids.length)}';
  return {
    for (final e in b.entries) 'entry ${e.id} ${id(e)}',
    for (final c in b.categories) 'category ${c.id} ${id(c)}',
    for (final x in b.budgets) 'budget ${x.category} ${id(x)}',
    for (final r in b.recurring) 'recurring ${r.id} ${id(r)}',
    for (final t in b.trash) 'trash ${t.entry.id} ${id(t)}',
    for (final (c, k) in b.dropped) 'dropped ${c.name} $k',
  };
}

typedef _Snapshot = ({
  List<Entry> entries,
  List<Category> categories,
  List<Budget> budgets,
  List<Recurring> recurring,
  List<Trashed> trash,
});

_Snapshot _snap(Ledger l) => (
  entries: List.of(l.entries),
  categories: List.of(l.categories),
  budgets: List.of(l.budgets),
  recurring: List.of(l.recurring),
  trash: List.of(l.trash),
);

/// What the ledger used to work out by comparing everything before and
/// after: every record not the very one it was, and every one gone.
WriteBatch _diff(_Snapshot was, Ledger now) {
  List<T> changed<T>(List<T> a, List<T> b, String Function(T) key) {
    final old = {for (final x in a) key(x): x};
    return [
      for (final x in b)
        if (!identical(old[key(x)], x)) x,
    ];
  }

  List<(Collection, String)> gone<T>(
    Collection c,
    List<T> a,
    List<T> b,
    String Function(T) key,
  ) {
    final kept = {for (final x in b) key(x)};
    return [
      for (final x in a)
        if (!kept.contains(key(x))) (c, key(x)),
    ];
  }

  return WriteBatch(
    entries: changed(was.entries, now.entries, (e) => e.id),
    categories: changed(was.categories, now.categories, (c) => c.id),
    budgets: changed(was.budgets, now.budgets, (b) => b.category),
    recurring: changed(was.recurring, now.recurring, (r) => r.id),
    trash: changed(was.trash, now.trash, (t) => t.entry.id),
    dropped: [
      ...gone(Collection.entry, was.entries, now.entries, (e) => e.id),
      ...gone(Collection.category, was.categories, now.categories, (c) => c.id),
      ...gone(Collection.budget, was.budgets, now.budgets, (b) => b.category),
      ...gone(Collection.recurring, was.recurring, now.recurring, (r) => r.id),
    ],
  );
}

void main() {
  group('UnitOfWork', () {
    test('nothing registered is an empty batch', () {
      final unit = UnitOfWork();
      expect(unit.isEmpty, isTrue);
      expect(unit.batch.isEmpty, isTrue);
    });

    test('a record registered twice is written once, as it ended', () {
      final unit = UnitOfWork();
      final first = _entry('e1');
      final last = _entry('e1', category: '交通');
      unit
        ..registerDirty(first)
        ..registerDirty(_entry('e2'))
        ..registerDirty(last);
      expect(unit.batch.entries.map((e) => e.id), ['e1', 'e2']);
      expect(unit.batch.entries.first, same(last));
    });

    test('a record deleted after it was changed is only dropped', () {
      final unit = UnitOfWork()
        ..registerDirty(Budget('#家用', 100))
        ..registerDeleted(Collection.budget, '#家用');
      expect(unit.batch.budgets, isEmpty);
      expect(unit.batch.dropped, [(Collection.budget, '#家用')]);
    });

    test('a record changed after it was deleted is only written', () {
      final unit = UnitOfWork()
        ..registerDeleted(Collection.budget, '#家用')
        ..registerDirty(Budget('#家用', 100));
      expect(unit.batch.dropped, isEmpty);
      expect(unit.batch.budgets.single.limit, 100);
      expect(unit.isEmpty, isFalse);
    });

    test('each kind of record goes to its own list', () {
      final category = Category('飲食', 'food', 0xFF000000, id: 'c1');
      const item = Recurring(
        id: 'r1',
        name: '房租',
        amount: 1,
        day: 1,
        account: 'bank',
        category: '居家',
      );
      final trashed = Trashed(_entry('t1'), DateTime.utc(2026, 9, 2));
      final batch =
          (UnitOfWork()
                ..registerAllDirty([category, item, trashed, Budget('飲食', 5)]))
              .batch;
      expect(batch.categories.single, same(category));
      expect(batch.recurring.single, same(item));
      expect(batch.trash.single, same(trashed));
      expect(batch.budgets.single.category, '飲食');
    });

    test('anything that is not a record kept is refused', () {
      expect(() => UnitOfWork().registerDirty('text'), throwsArgumentError);
    });
  });

  // Each change that touches many records hands over exactly what the old
  // way, comparing the whole book before and after, would have found.
  for (final seed in [1, 2, 3, 5, 8, 13, 21, 34]) {
    test('a change writes what a full comparison finds (seed $seed)', () async {
      final r = Random(seed);
      const names = ['飲食', '交通', '居家', '娛樂', '早餐'];
      const tags = ['家用', '旅行', '禮物'];
      const shops = ['便當店', '捷運', '房東'];
      final source = _Batches();
      final ledger = Ledger(
        today: DateTime.utc(2026, 10, 4),
        accounts: const [Account('bank', '銀行', AccountKind.bank, 1000)],
        categories: [
          for (final n in names)
            Category(n, 'other', 0xFF000000, parent: n == '早餐' ? '飲食' : null),
        ],
        entries: [
          for (var i = 0; i < 40; i++)
            Entry(
              id: 'e$i',
              date: DateTime.utc(2026, 1 + r.nextInt(9), 1 + r.nextInt(28)),
              type: EntryType.expense,
              amount: 10 + r.nextInt(500),
              account: 'bank',
              category: names[r.nextInt(names.length)],
              merchant: shops[r.nextInt(shops.length)],
              tags: [if (r.nextBool()) tags[r.nextInt(tags.length)]],
            ),
        ],
        holdings: const [],
        budgets: [Budget('飲食', 500), Budget('#家用', 300), Budget('#旅行', 90)],
        recurring: [
          for (final (i, n) in names.indexed)
            Recurring(
              id: 'r$i',
              name: n,
              amount: 100,
              day: 5,
              account: 'bank',
              category: n,
            ),
        ],
        dataSource: source,
      );
      for (var i = 0; i < 10; i++) {
        ledger.remove('e${r.nextInt(40)}');
      }
      await ledger.settled;
      final ids = <Object, int>{};
      var compared = 0;
      for (var step = 0; step < 30; step++) {
        final live = [for (final c in ledger.categories) c.name];
        final was = _snap(ledger);
        final count = source.kept.length;
        final what = r.nextInt(5);
        switch (what) {
          case 0 when live.length > 1:
            ledger.mergeCategory(
              live[r.nextInt(live.length)],
              live[r.nextInt(live.length)],
            );
          case 1:
            final pick = r.nextInt(tags.length + 1);
            ledger.renameTag(
              tags[r.nextInt(tags.length)],
              pick == tags.length ? '' : tags[pick],
            );
          case 2:
            ledger.renameMerchant(
              shops[r.nextInt(shops.length)],
              r.nextInt(4) == 0 ? '' : shops[r.nextInt(shops.length)],
            );
          case 3 when live.isNotEmpty:
            final c = ledger.category(live[r.nextInt(live.length)]);
            ledger.updateCategory(c.name, c.copyWith(archived: !c.archived));
          case 4:
            ledger.setBudget(
              r.nextBool() ? '#${tags[r.nextInt(tags.length)]}' : live.first,
              100 + r.nextInt(900),
            );
          default:
            continue;
        }
        await ledger.settled;
        if (source.kept.length == count) continue;
        expect(source.kept, hasLength(count + 1), reason: 'one batch a change');
        compared++;
        final made = source.kept.last;
        expect(
          _shape(made, ids),
          _shape(_diff(was, ledger), ids),
          reason: 'step $step action $what',
        );
      }
      // Most steps change something; a run that compared nothing proves
      // nothing.
      expect(compared, greaterThan(15));
    });
  }
}
