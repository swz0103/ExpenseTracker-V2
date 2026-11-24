import 'package:kernel/kernel.dart';
import 'package:test/test.dart';

import '../support/book.dart';

/// The intent of an unknown kind, as a removed owner's would be.
final class Stranger extends LedgerIntent {
  const Stranger()
    : super(id: const IntentId('x'), date: const Day.stored(20260101), seq: 1);
  @override
  IntentType get type => const IntentType('stranger');
}

/// A rule that loses a dollar on the way.
final class Leaky implements PostingRule<Move> {
  const Leaky();
  @override
  Iterable<String> streams(Move intent) => const [];
  @override
  Posted post(Move i, RuleContext context) =>
      Lines([Line(i.from, -i.amount, twd), Line(i.to, i.amount - 1, twd)]);
}

WriteReport written(JournalResult r) => switch (r) {
  Written(:final report) => report,
  final JournalRefusal refused => throw StateError('refused: $refused'),
};

void main() {
  test('an intent is kept with its balanced lines', () {
    final b = book();
    final report = written(
      b.journal.put(Move('m', day(3, 1), 1, from: bank, to: food, amount: 120)),
    );
    expect((report.posted, report.postings), (1, 2));
    expect(report.stale, isEmpty);
    expect(b.store.sums(), {
      (bank, twd): (amount: -120, quantity: BigInt.zero),
      (food, twd): (amount: 120, quantity: BigInt.zero),
    });
    final p = b.store.postingsOfIntent(const IntentId('m'));
    expect(
      [for (final x in p) (x.line, x.date, x.seq)],
      [(0, day(3, 1), 1), (1, day(3, 1), 1)],
    );
  });

  test('what goes with a write is kept in its transaction, or not at all', () {
    final b = book();
    final mark = (rules: 1, revision: 7);
    written(
      b.journal.putAll([
        Move('m', day(3, 1), 1, from: bank, to: food, amount: 5),
      ], also: () => b.store.keepMark(mark)),
    );
    expect(b.store.mark, mark);
    final refused = b.journal.putAll([
      Move('n', day(3, 1), 2, from: bank, to: food, amount: -5),
    ], also: () => b.store.keepMark((rules: 1, revision: 8)));
    expect(refused, isA<RuleRejected>());
    expect(b.store.mark, mark);
    written(
      b.journal.delete(
        const IntentId('m'),
        also: () => b.store.keepMark((rules: 1, revision: 9)),
      ),
    );
    written(
      b.journal.rematerialise(
        'jar',
        also: () => b.store.keepMark((rules: 1, revision: 10)),
      ),
    );
    expect(b.store.mark, (rules: 1, revision: 10));
  });

  test('an edit replaces the lines it had', () {
    final b = book();
    written(
      b.journal.put(Move('m', day(3, 1), 1, from: bank, to: food, amount: 120)),
    );
    written(
      b.journal.put(Move('m', day(3, 2), 1, from: cash, to: food, amount: 50)),
    );
    expect(b.store.sums(), {
      (cash, twd): (amount: -50, quantity: BigInt.zero),
      (food, twd): (amount: 50, quantity: BigInt.zero),
    });
    expect(b.store.intentCount, 1);
  });

  group('refused, with nothing changed', () {
    test('lines that do not come to zero', () {
      final r = IntentRegistry()
        ..register<Move>(
          const IntentSpec(type: Move.kind, owner: owner, rule: Leaky()),
        );
      final b = book(with_: r);
      final refused = b.journal.put(
        Move('m', day(3, 1), 1, from: bank, to: food, amount: 120),
      );
      expect(refused, isA<Unbalanced>());
      final u = refused as Unbalanced;
      // -120 + 119 = -1.
      expect(
        (u.intent, u.currency, u.residual),
        (const IntentId('m'), twd, -1),
      );
      expect(b.store.intentCount, 0);
    });

    test('an account the book has not', () {
      final refused = book().journal.put(
        Move(
          'm',
          day(3, 1),
          1,
          from: bank,
          to: const AccountId('?'),
          amount: 1,
        ),
      );
      expect((refused as UnknownAccount).account, const AccountId('?'));
    });

    test('a line in another currency than its account', () {
      final b = book(with_: registry(amendable: false));
      final refused = b.journal.put(
        Move('m', day(3, 1), 1, from: bank, to: dollars, amount: 1),
      );
      final m = refused as CurrencyMismatch;
      expect((m.account, m.expected, m.got), (dollars, usd, twd));
    });

    test('a kind nobody here posts', () {
      final refused = book().journal.put(const Stranger());
      expect((refused as UnknownIntentType).type, const IntentType('stranger'));
    });

    test('a rule that refuses, and a value no amender reads', () {
      final b = book();
      final r = b.journal.put(
        Move('m', day(3, 1), 1, from: bank, to: food, amount: 0),
      );
      expect(((r as RuleRejected).code, r.detail), ('badAmount', ''));
      final slot = b.journal.put(
        Move(
          'n',
          day(3, 1),
          2,
          from: bank,
          to: food,
          amount: 1,
          amendments: const {'?': 1},
        ),
      );
      expect((slot as UnknownAmendment).slot, '?');
      final closed = book(with_: registry(amendable: false)).journal.put(
        Move(
          'n',
          day(3, 1),
          2,
          from: bank,
          to: food,
          amount: 1,
          amendments: const {'fx': 1},
        ),
      );
      expect((closed as UnknownAmendment).slot, 'fx');
    });

    test('taking away what is not kept', () {
      final r = book().journal.delete(const IntentId('none'));
      expect((r as IntentNotFound).intent, const IntentId('none'));
    });

    test('putAll: one refused and none kept', () {
      final b = book();
      final r = b.journal.putAll([
        Move('a', day(3, 1), 1, from: bank, to: food, amount: 5),
        Move('b', day(3, 1), 2, from: bank, to: food, amount: -5),
      ]);
      expect((r as RuleRejected).intent, const IntentId('b'));
      expect(b.store.intentCount, 0);
      expect(b.store.postingCount, 0);
    });
  });

  test('an amender restates a line in another currency', () {
    final b = book();
    final needed = b.journal.put(
      Move('fx', day(3, 1), 1, from: bank, to: dollars, amount: 3210),
    );
    expect(((needed as RuleRejected).code, needed.detail), ('fx.needed', 'fx'));
    written(
      b.journal.put(
        Move(
          'fx',
          day(3, 1),
          1,
          from: bank,
          to: dollars,
          amount: 3210,
          amendments: const {'fx': 10000},
        ),
      ),
    );
    expect(b.store.sums(), {
      (bank, twd): (amount: -3210, quantity: BigInt.zero),
      (dollars, usd): (amount: 10000, quantity: BigInt.zero),
      // The trading account takes the far side of each currency.
      (trading, twd): (amount: 3210, quantity: BigInt.zero),
      (trading, usd): (amount: -10000, quantity: BigInt.zero),
    });
  });

  group('streams', () {
    late ({
      Journal journal,
      MemoryPostingStore store,
      Map<IntentId, LedgerIntent> kept,
    })
    b;
    JournalResult keep(LedgerIntent i) {
      final r = b.journal.put(i);
      if (r is Written) b.kept[i.id] = i;
      return r;
    }

    setUp(() {
      b = book();
      written(keep(Beans('in', Day.stored(20260301), 1, 10, 100)));
      written(keep(Beans('out', Day.stored(20260303), 2, -6, -60)));
    });

    test('a rule reads the postings before its intent', () {
      final r = keep(Beans('more', Day.stored(20260304), 3, -5, -50));
      // 10 - 6 = 4 held, 5 taken.
      expect(
        ((r as RuleRejected).intent, r.code),
        (const IntentId('more'), 'tooFew'),
      );
    });

    test('an earlier intent changed posts the later ones again, '
        'and a later one refusing refuses the change', () {
      final r = keep(Beans('in', Day.stored(20260301), 1, 5, 50));
      // 5 held, 6 taken by 'out', which is named.
      expect((r as RuleRejected).intent, const IntentId('out'));
      expect(b.store.sums()[(jar, twd)], (
        amount: 40,
        quantity: BigInt.from(4),
      ));
      final ok = written(keep(Beans('in', Day.stored(20260301), 1, 8, 80)));
      expect(ok.posted, 2);
      expect(b.store.sums()[(jar, twd)], (
        amount: 20,
        quantity: BigInt.from(2),
      ));
    });

    test('moved past a later intent, the later one no longer sees it', () {
      final r = keep(Beans('in', Day.stored(20260305), 1, 10, 100));
      expect((r as RuleRejected).intent, const IntentId('out'));
    });

    test('taking one away posts the rest again', () {
      final r = b.journal.delete(const IntentId('in'));
      expect((r as RuleRejected).intent, const IntentId('out'));
      written(b.journal.delete(const IntentId('out')));
      written(b.journal.delete(const IntentId('in')));
      expect(b.store.postingCount, 0);
    });

    test('rematerialise posts a stream again from what the source says', () {
      b.kept[const IntentId('in')] = Beans(
        'in',
        Day.stored(20260301),
        1,
        10,
        70,
      );
      final r = written(b.journal.rematerialise('jar'));
      expect(r.posted, 2);
      // 70 in, 60 out.
      expect(b.store.sums()[(jar, twd)], (
        amount: 10,
        quantity: BigInt.from(4),
      ));
    });

    test('a follower nobody can post stays as written', () {
      // The same store, read by an app that no longer knows beans.
      final without = IntentRegistry()
        ..register<Move>(
          const IntentSpec(type: Move.kind, owner: owner, rule: MoveRule()),
        );
      final j = Journal(
        registry: without,
        accounts: tree(),
        store: b.store,
        source: (id) => b.kept[id],
      );
      final r = written(j.rematerialise('jar'));
      expect(r.posted, 0);
      expect(r.stale, [const IntentId('in'), const IntentId('out')]);
      expect(b.store.sums()[(jar, twd)], (
        amount: 40,
        quantity: BigInt.from(4),
      ));
      final gone = j.delete(const IntentId('in'));
      expect((gone as UnknownIntentType).type, Beans.kind);
      final over = j.put(
        Move('in', day(3, 1), 1, from: bank, to: food, amount: 1),
      );
      expect(over, isA<UnknownIntentType>());
    });

    test('a follower the source has lost stays as written', () {
      b.kept.remove(const IntentId('out'));
      final r = written(b.journal.rematerialise('jar'));
      expect(r.stale, [const IntentId('out')]);
    });

    test('a batch is posted in book order, whatever order it is given in: '
        'a later intent listed first reads the earlier one', () {
      final r = written(
        b.journal.putAll([
          Beans('late', Day.stored(20260306), 4, -7, -70),
          Beans('early', Day.stored(20260305), 3, 5, 50),
        ]),
      );
      expect(r.posted, 2);
      // 10 - 6 + 5 = 9 held, 7 taken.
      expect(b.store.sums()[(jar, twd)], (
        amount: 20,
        quantity: BigInt.from(2),
      ));
    });

    test('a stale follower leaves what goes with the write unwritten: no '
        'mark past it', () {
      b.kept.remove(const IntentId('out'));
      var marked = false;
      final r = written(
        b.journal.putAll([
          Beans('in', Day.stored(20260301), 1, 12, 120),
        ], also: () => marked = true),
      );
      expect(r.stale, [const IntentId('out')]);
      expect(marked, isFalse);
    });
  });

  test('the streams of an intent: its rule\'s and its amenders\', none for '
      'a kind nobody posts', () {
    final b = book();
    expect(b.journal.streamsOf(Beans('x', Day.stored(20260301), 1, 1, 1)), [
      'jar',
    ]);
    expect(b.journal.streamsOf(const Stranger()), isEmpty);
  });
}
