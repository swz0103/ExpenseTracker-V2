import 'package:kernel/kernel.dart';
import 'package:test/test.dart';

import '../support/book.dart';

void main() {
  test('a whole book posted afresh gives what the memory store gives', () {
    final fresh = FreshPostingStore();
    final memory = MemoryPostingStore();
    final kept = <IntentId, LedgerIntent>{};
    Journal over(PostingStore store) => Journal(
      registry: registry(),
      accounts: tree(),
      store: store,
      source: (id) => kept[id],
    );
    final intents = <LedgerIntent>[
      Move('pay', day(1, 1), 1, from: food, to: bank, amount: 500),
      Beans('in', day(1, 2), 2, 10, 100),
      Move(
        'fx',
        day(1, 3),
        3,
        from: bank,
        to: dollars,
        amount: 32,
        amendments: const {'fx': 100},
      ),
      Beans('out', day(1, 4), 4, -4, -40),
    ];
    for (final j in [over(fresh), over(memory)]) {
      expect(j.putAll(intents), isA<Written>());
    }
    expect(fresh.sums(), memory.sums());
    expect(
      fresh.sums(from: day(1, 2), until: day(1, 3)),
      memory.sums(from: day(1, 2), until: day(1, 3)),
    );
    expect(fresh.subSums(jar), memory.subSums(jar));
    expect(
      fresh.subSums(jar, until: day(1, 2)),
      memory.subSums(jar, until: day(1, 2)),
    );
    expect(fresh.postingsOf(jar), memory.postingsOf(jar));
    expect(
      fresh.postingsOf(jar, before: (date: day(1, 3), seq: 0)),
      memory.postingsOf(jar, before: (date: day(1, 3), seq: 0)),
    );
    expect(
      fresh.postingsOfIntent(const IntentId('fx')),
      memory.postingsOfIntent(const IntentId('fx')),
    );
    expect(fresh.postingsOfIntent(const IntentId('none')), isEmpty);
    expect(
      [
        for (final r in fresh.inStream('jar', from: (date: day(1, 3), seq: 0)))
          r.id.value,
      ],
      ['out'],
    );
    expect(
      (fresh.intentCount, fresh.postingCount),
      (memory.intentCount, memory.postingCount),
    );
    expect(
      [for (final r in fresh.intents) r.id.value],
      ['pay', 'in', 'fx', 'out'],
    );
    expect(fresh.postings, hasLength(memory.postingCount));
    expect(fresh.intent(const IntentId('in'))!.streams, ['jar']);
  });

  test('a refused batch leaves nothing behind; posting twice or taking '
      'away is not posting afresh', () {
    final fresh = FreshPostingStore()..keepMark((rules: 1, revision: 1));
    final j = Journal(
      registry: registry(),
      accounts: tree(),
      store: fresh,
      source: (_) => null,
    );
    expect(j.put(Beans('in', day(1, 2), 1, 10, 100)), isA<Written>());
    final r = j.putAll([
      Beans('more', day(1, 3), 2, 5, 50),
      Beans('out', day(1, 4), 3, -99, -1),
    ]);
    expect(r, isA<RuleRejected>());
    expect((fresh.intentCount, fresh.postingCount), (1, 2));
    expect(
      fresh.inStream('jar', from: (date: day(1, 1), seq: 0)),
      hasLength(1),
    );
    expect(() => fresh.put(fresh.intents.single, const []), throwsStateError);
    expect(() => fresh.remove(const IntentId('in')), throwsStateError);
    expect(
      () => fresh.transaction(() => fresh.transaction(() => 1)),
      throwsStateError,
    );
    fresh.keepAccounts(tree().all);
    expect(fresh.accounts(), hasLength(6));
    expect(fresh.mark, (rules: 1, revision: 1));
    fresh.clear();
    expect((fresh.intentCount, fresh.postingCount, fresh.mark), (0, 0, null));
  });
}
