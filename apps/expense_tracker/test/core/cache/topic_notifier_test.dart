import 'package:expense_tracker/src/core/ledger/cache/topic.dart';
import 'package:expense_tracker/src/core/ledger/cache/topic_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each change is counted, in all and for its topic', () {
    final notifier = TopicNotifier();
    expect(notifier.revision, 0);
    notifier.count({Topic.entries, Topic.accounts});
    notifier.count({Topic.entries});
    expect(notifier.revision, 2);
    expect(notifier.revisionOf(Topic.entries), 2);
    expect(notifier.revisionOf(Topic.accounts), 1);
    expect(notifier.revisionOf(Topic.budgets), 0);
  });

  test('a change of no topic still moves the revision on', () {
    final notifier = TopicNotifier();
    notifier.count(const {});
    expect(notifier.revision, 1);
    for (final topic in Topic.values) {
      expect(notifier.revisionOf(topic), 0);
    }
  });

  test('a watcher hears of its own topics only', () {
    final notifier = TopicNotifier();
    var budgets = 0;
    var market = 0;
    notifier.watch({Topic.budgets}).addListener(() => budgets++);
    notifier.watch({Topic.market}).addListener(() => market++);

    notifier.announce({Topic.budgets});
    expect((budgets, market), (1, 0));
    notifier.announce({Topic.market, Topic.budgets});
    expect((budgets, market), (2, 1));
    notifier.announce({Topic.entries});
    expect((budgets, market), (2, 1));
  });

  test('every watcher hears of how amounts are shown', () {
    final notifier = TopicNotifier();
    var heard = 0;
    notifier.watch({Topic.entries}).addListener(() => heard++);
    notifier.watch(const {}).addListener(() => heard++);
    notifier.announce({Topic.display});
    expect(heard, 2);
  });

  test('one watching several topics hears once for each that changes', () {
    final notifier = TopicNotifier();
    var heard = 0;
    notifier.watch({Topic.entries, Topic.accounts}).addListener(() => heard++);
    notifier.announce({Topic.entries, Topic.accounts});
    expect(heard, 2);
  });

  test('announcing to nobody does no harm', () {
    final notifier = TopicNotifier();
    expect(() => notifier.announce(Topic.values.toSet()), returnsNormally);
  });

  test('two watchers of one topic both hear it, and can stop', () {
    final notifier = TopicNotifier();
    var a = 0;
    var b = 0;
    void onA() => a++;
    final first = notifier.watch({Topic.recurring})..addListener(onA);
    notifier.watch({Topic.recurring}).addListener(() => b++);
    notifier.announce({Topic.recurring});
    expect((a, b), (1, 1));
    first.removeListener(onA);
    notifier.announce({Topic.recurring});
    expect((a, b), (1, 2));
  });
}
