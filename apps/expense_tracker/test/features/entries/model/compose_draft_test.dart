import 'dart:convert';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/codec/record_json.dart';
import 'package:expense_tracker/src/features/entries/model/compose_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final entry = Entry(
    id: 'e1',
    date: DateTime.utc(2026, 10, 4),
    type: EntryType.expense,
    amount: 900,
    account: 'bank',
    category: '飲食',
    note: '聚餐',
  );

  test('a draft put aside reads back as it was', () {
    final kept = ComposeDraft(entry, 'r1.etr', [('ann', 300), ('bo', 200)]);
    final back = ComposeDraft.read(kept.toJson())!;
    expect(jsonEncode(entryToJson(back.entry)), jsonEncode(entryToJson(entry)));
    expect(back.receipt, 'r1.etr');
    expect(back.lent, [('ann', 300), ('bo', 200)]);

    final plain = ComposeDraft.read(ComposeDraft(entry, null).toJson())!;
    expect((plain.receipt, plain.lent), (null, null));
  });

  test('a draft left on 今天 follows today when reopened (ENT-16)', () {
    // Put aside on 10/4 with the date it opened on, 10/4.
    final left = ComposeDraft.read(
      ComposeDraft(entry, null, null, DateTime.utc(2026, 10, 4)).toJson(),
    )!;
    expect(left.savedOn, DateTime.utc(2026, 10, 4));
    // Reopened on 10/6: the date is 10/6.
    expect(left.dateOn(DateTime.utc(2026, 10, 6)), DateTime.utc(2026, 10, 6));
    // Put aside on 10/5 with 10/4 picked: it stays 10/4.
    final picked = ComposeDraft(entry, null, null, DateTime.utc(2026, 10, 5));
    expect(picked.dateOn(DateTime.utc(2026, 10, 6)), DateTime.utc(2026, 10, 4));
    // A draft kept before the day was noted keeps its date.
    expect(
      ComposeDraft(entry, null).dateOn(DateTime.utc(2026, 10, 6)),
      DateTime.utc(2026, 10, 4),
    );
  });

  test('a draft that cannot be read is left out, never thrown', () {
    expect(ComposeDraft.read(null), isNull);
    expect(ComposeDraft.read('not json'), isNull);
    expect(ComposeDraft.read('[1, 2]'), isNull);
    expect(ComposeDraft.read('{"receipt": "r1.etr"}'), isNull);
    expect(ComposeDraft.read('{"entry": {"id": 3}}'), isNull);
  });

  test('parts of a draft of the wrong kind are left out', () {
    final json = jsonEncode({
      'entry': entryToJson(entry),
      'receipt': 42,
      'lent': [
        ['ann', 300],
        ['bo', 'two hundred'],
        'nobody',
      ],
    });
    final back = ComposeDraft.read(json)!;
    expect(back.receipt, isNull);
    expect(back.lent, [('ann', 300)]);
  });
}
