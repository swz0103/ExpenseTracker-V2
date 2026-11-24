import 'package:ledger_entries/model.dart';
import 'package:ledger_entries/rules.dart';
import 'package:test/test.dart';

final _day = DateTime.utc(2026, 10, 1);

Entry _purchase({
  int amount = 100,
  int? home,
  List<(String, int)> parts = const [],
  List<String> tags = const [],
}) => Entry(
  id: 'p',
  date: _day,
  type: EntryType.expense,
  amount: amount,
  account: 'bank',
  category: parts.isEmpty ? '飲食' : parts.first.$1,
  parts: parts,
  tags: tags,
  home: home,
);

Entry _refund(String id, RefundShare share, int amount) => Entry(
  id: id,
  date: _day,
  type: EntryType.income,
  amount: amount,
  account: 'bank',
  category: share.category,
  parts: share.parts,
  tags: share.tags,
  home: share.home,
  refundOf: 'p',
);

void main() {
  group('worth at home (D62)', () {
    test('three equal refunds of a NT\$1,001 purchase sum to 1,001', () {
      final p = _purchase(amount: 300, home: 1001);
      final earlier = <Entry>[];
      final homes = <int?>[];
      for (var i = 0; i < 3; i++) {
        final share = refundShare(p, 100, earlier: earlier);
        homes.add(share.home);
        earlier.add(_refund('r$i', share, 100));
      }
      // 1001 x 100 / 300 = 333.67 -> 334; then 667 x 100 / 200 = 333.5
      // -> 334; the last takes the rest, 1001 - 668 = 333.
      expect(homes, [334, 334, 333]);
    });

    test('a refund of the whole takes the whole worth', () {
      expect(refundShare(_purchase(amount: 300, home: 1001), 300).home, 1001);
    });

    test('a purchase in NT\$ has no worth to share', () {
      expect(refundShare(_purchase(), 50).home, isNull);
    });
  });

  group('split and tags (D65)', () {
    final split = _purchase(
      parts: const [('飲食', 60), ('交通', 40)],
      tags: const ['旅遊'],
    );

    test('a full refund gives back every part, with the tags', () {
      final share = refundShare(split, 100);
      expect(share.parts, [('飲食', 60), ('交通', 40)]);
      expect(share.category, '飲食');
      expect(share.tags, ['旅遊']);
    });

    test('a partial refund shares by the parts left; the last takes the '
        'rest', () {
      final first = refundShare(split, 50);
      // 50 x 60 / 100 = 30, 50 x 40 / 100 = 20.
      expect(first.parts, [('飲食', 30), ('交通', 20)]);
      final second = refundShare(split, 50, earlier: [_refund('a', first, 50)]);
      // Left 30 and 20: all of it.
      expect(second.parts, [('飲食', 30), ('交通', 20)]);
    });

    test('small refunds never give back more than a part had', () {
      final earlier = <Entry>[];
      final back = <String, int>{};
      for (var i = 0; i < 100; i++) {
        final share = refundShare(split, 1, earlier: earlier);
        final r = _refund('r$i', share, 1);
        earlier.add(r);
        for (final (name, value)
            in r.parts.isEmpty ? [(r.category, 1)] : r.parts) {
          back[name] = (back[name] ?? 0) + value;
        }
      }
      // A hundred refunds of 1: exactly 60 and 40 back.
      expect(back, {'飲食': 60, '交通': 40});
    });

    test('a refund kept without a split counted under its category', () {
      final old = Entry(
        id: 'old',
        date: _day,
        type: EntryType.income,
        amount: 60,
        account: 'bank',
        category: '飲食',
        refundOf: 'p',
      );
      // 飲食 has nothing left: the remaining 40 is 交通's.
      final share = refundShare(split, 40, earlier: [old]);
      expect(share.parts, isEmpty);
      expect(share.category, '交通');
    });

    test('a purchase not split gives its category and no parts', () {
      final share = refundShare(_purchase(tags: const ['家用']), 30);
      expect(share.parts, isEmpty);
      expect(share.category, '飲食');
      expect(share.tags, ['家用']);
    });
  });
}
