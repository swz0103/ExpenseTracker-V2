// A line whose quantity the file cannot keep is refused by the
// journal, whatever the store, as a typed refusal (r14 F5): never an
// ArgumentError out of the file's `put`, never kept by the memory store.
import 'package:kernel/kernel.dart';
import 'package:test/test.dart';

import '../support/book.dart';

final class _Raw extends LedgerIntent {
  _Raw(String id, Day date, int seq, this.lines)
    : super(id: IntentId(id), date: date, seq: seq);
  static const kind = IntentType('raw');
  final List<Line> lines;
  @override
  IntentType get type => kind;
}

final class _RawRule implements PostingRule<_Raw> {
  const _RawRule();
  @override
  Iterable<String> streams(_Raw i) => const [];
  @override
  Posted post(_Raw i, RuleContext c) => Lines(i.lines);
}

void main() {
  test(
    'a line with more quantity than a file keeps is refused, nothing kept',
    () {
      final reg = registry()
        ..register<_Raw>(
          IntentSpec(type: _Raw.kind, owner: owner, rule: const _RawRule()),
        );
      final env = book(with_: reg);
      final r = env.journal.put(
        _Raw('raw', day(6, 1), 1, [
          Line(jar, 5, twd, quantity: maxQuantity + BigInt.one, sub: 'a'),
          Line(cash, -5, twd),
        ]),
      );
      expect(r, isA<UnkeepableQuantity>(), reason: 'kept: $r');
      expect(env.store.intentCount, 0);
    },
  );

  test('two lines each keepable whose quantities together pass a file\'s '
      'sum (2^63 units) on one account are refused too', () {
    final reg = registry()
      ..register<_Raw>(
        IntentSpec(type: _Raw.kind, owner: owner, rule: const _RawRule()),
      );
    final env = book(with_: reg);
    final r = env.journal.put(
      _Raw('raw', day(6, 1), 1, [
        Line(jar, 5, twd, quantity: maxQuantity, sub: 'a'),
        Line(jar, 5, twd, quantity: maxQuantity, sub: 'b'),
        Line(cash, -10, twd),
      ]),
    );
    expect(r, isA<UnkeepableQuantity>(), reason: 'kept: $r');
  });
}
