import 'dart:math';

import 'package:expense_tracker/src/core/ledger/cache/query_cache.dart';
import 'package:expense_tracker/src/core/ledger/cache/topic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an answer is worked out once for a key', () {
    final cache = QueryCache();
    var made = 0;
    int work() => ++made;

    expect(cache.remember('sum', work), 1);
    expect(cache.remember('sum', work), 1);
    expect(made, 1);
    expect(cache.length, 1);
  });

  test('each key has its own answer, a record of arguments included', () {
    final cache = QueryCache();
    expect(cache.remember(('month', 10), () => 'a'), 'a');
    expect(cache.remember(('month', 11), () => 'b'), 'b');
    // An equal record is the same key, though it is a new object.
    expect(cache.remember(('month', 10), () => 'never'), 'a');
    expect(cache.length, 2);
  });

  test('an answer with no topics named rests on all of them', () {
    for (final topic in Topic.all) {
      final cache = QueryCache();
      var made = 0;
      cache.remember('k', () => ++made);
      cache.forget({topic});
      cache.remember('k', () => ++made);
      expect(made, 2, reason: '$topic');
    }
  });

  test('how amounts are shown is not something an answer rests on', () {
    final cache = QueryCache();
    var made = 0;
    cache.remember('k', () => ++made);
    cache.forget({Topic.display});
    cache.remember('k', () => ++made);
    expect(made, 1);
  });

  test('a change throws away what rests on it and keeps the rest', () {
    final cache = QueryCache();
    final onBudgets = <String>[];
    cache.remember('budget', () => Object(), reads: {Topic.budgets});
    final statement = cache.remember(
      'statement',
      () => Object(),
      reads: {Topic.entries, Topic.accounts},
    );

    cache.forget({Topic.budgets});

    expect(cache.length, 1);
    expect(
      identical(
        cache.remember('statement', () => Object(), reads: {Topic.entries}),
        statement,
      ),
      isTrue,
    );
    cache.remember('budget', () {
      onBudgets.add('again');
      return Object();
    }, reads: {Topic.budgets});
    expect(onBudgets, ['again']);
  });

  test('an answer that is null is kept like any other', () {
    final cache = QueryCache();
    var made = 0;
    String? work() {
      made++;
      return null;
    }

    expect(cache.remember<String?>('none', work), isNull);
    expect(cache.remember<String?>('none', work), isNull);
    expect(made, 1);
  });

  test('a computation that throws leaves nothing kept', () {
    final cache = QueryCache();
    expect(
      () => cache.remember<int>('k', () => throw StateError('no')),
      throwsStateError,
    );
    expect(cache.length, 0);
    expect(cache.remember('k', () => 7), 7);
  });

  test('forgetting nothing, or forgetting from an empty cache, is fine', () {
    final cache = QueryCache();
    cache.forget({Topic.entries});
    cache.remember('k', () => 1);
    cache.forget(const {});
    expect(cache.length, 1);
  });

  for (final seed in [3, 11, 99]) {
    test(
      'it behaves like a plain list of answers and what they read ($seed)',
      () {
        final random = Random(seed);
        final cache = QueryCache();
        // The reference: every key's answer and what it read, forgotten the
        // slow, obvious way.
        final answers = <int, int>{};
        final reads = <int, Set<Topic>>{};
        final topics = Topic.values;
        var made = 0;

        for (var step = 0; step < 500; step++) {
          if (random.nextInt(4) == 0) {
            final changed = {
              for (var i = 0; i < random.nextInt(3); i++)
                topics[random.nextInt(topics.length)],
            };
            cache.forget(changed);
            for (final key in answers.keys.toList()) {
              if (reads[key]!.any(changed.contains)) {
                answers.remove(key);
                reads.remove(key);
              }
            }
          } else {
            final key = random.nextInt(12);
            final on = {
              for (var i = 0; i <= random.nextInt(3); i++)
                topics[random.nextInt(topics.length)],
            };
            final got = cache.remember(key, () => ++made, reads: on);
            final wanted = answers.putIfAbsent(key, () {
              reads[key] = on;
              return made;
            });
            expect(got, wanted, reason: 'step $step key $key');
          }
          expect(cache.length, answers.length, reason: 'step $step');
        }
      },
    );
  }
}
