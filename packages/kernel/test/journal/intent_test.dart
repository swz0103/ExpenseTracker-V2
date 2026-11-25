import 'package:kernel/kernel.dart';
import 'package:test/test.dart';

import '../support/book.dart';

void main() {
  test('a kind or a slot is registered once', () {
    final r = registry();
    expect(
      () => r.register<Move>(
        const IntentSpec(type: Move.kind, owner: owner, rule: MoveRule()),
      ),
      throwsStateError,
    );
    expect(
      () => r.amend(
        const Amender(slot: 'fx', owner: owner, order: 1, amend: convert),
      ),
      throwsStateError,
    );
    expect(r.types, [Move.kind, Beans.kind]);
    expect(r[const IntentType('none')], isNull);
    expect(r.amenderOf('none'), isNull);
  });

  test('amenders run lowest order first', () {
    Posted keep(Amendment a) => Lines(a.lines);
    final r = IntentRegistry()
      ..amend(Amender(slot: 'late', owner: owner, order: 20, amend: keep))
      ..amend(Amender(slot: 'early', owner: owner, order: 10, amend: keep));
    expect([for (final a in r.amenders) a.slot], ['early', 'late']);
  });

  test('a spec casts to its kind for the journal', () {
    final spec = registry()[Move.kind]!;
    final m = Move(
      'm',
      Day.stored(20260101),
      4,
      from: bank,
      to: food,
      amount: 3,
    );
    expect(spec.streamsOf(m), isEmpty);
    expect(spec.touchesOf(m), [bank, food]);
    expect(
      registry()[Beans.kind]!.touchesOf(
        Beans('b', Day.stored(20260101), 1, 1, 1),
      ),
      isEmpty,
    );
    expect(m.position, (date: Day.stored(20260101), seq: 4));
    expect(m.amendments, isEmpty);
    final posted = spec.linesOf(
      m,
      RuleContext(tree(), MemoryPostingStore(), m.position),
    );
    expect([for (final l in (posted as Lines).lines) l.amount], [-3, 3]);
    final refused = const MoveRule().post(
      Move('m', Day.stored(20260101), 4, from: bank, to: food, amount: 0),
      RuleContext(tree(), MemoryPostingStore(), m.position),
    ) as Refused;
    expect((refused.code, refused.detail), ('badAmount', ''));
  });
}
