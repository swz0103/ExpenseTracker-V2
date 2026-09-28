import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:test/test.dart';

void main() {
  final twd = Currency('TWD', 2);
  test('versioned AND query survives serialization without losing filters', () {
    final account = PublicId.generate();
    final category = PublicId.generate();
    final tag = PublicId.generate();
    final merchant = PublicId.generate();
    final query = LedgerSearchQuery(
      from: BusinessDate(2026, 2, 1),
      through: BusinessDate(2026, 2, 28),
      accountId: account,
      categoryId: category,
      tagId: tag,
      merchantId: merchant,
      currency: twd,
      kind: PostingKind.expense,
      minAbsAmount: Money(twd, BigInt.from(100)),
      maxAbsAmount: Money(twd, BigInt.from(500)),
      noteContains: '午餐',
    );
    expect(LedgerSearchQuery.fromJson(query.toJson()).toJson(), query.toJson());
    expect(LedgerSearchQuery.fromJson({'version': 1}).toJson(), {'version': 1});
  });

  test('invalid ranges and cross-currency amount comparisons fail closed', () {
    expect(
      () => LedgerSearchQuery(
        from: BusinessDate(2026, 3, 1),
        through: BusinessDate(2026, 2, 28),
      ),
      throwsFormatException,
    );
    expect(
      () => LedgerSearchQuery(minAbsAmount: Money(twd, BigInt.one)),
      throwsFormatException,
    );
    expect(
      () => LedgerSearchQuery(
        currency: twd,
        minAbsAmount: Money(Currency('USD', 2), BigInt.one),
      ),
      throwsFormatException,
    );
    expect(
      () => LedgerSearchQuery(
        currency: twd,
        minAbsAmount: Money(twd, BigInt.from(500)),
        maxAbsAmount: Money(twd, BigInt.from(100)),
      ),
      throwsFormatException,
    );
    expect(
      () => LedgerSearchQuery(
        currency: twd,
        minAbsAmount: Money(twd, -BigInt.one),
      ),
      throwsFormatException,
    );
  });

  test(
    'unknown versions, fields and malformed bounds never broaden search',
    () {
      for (final value in <Map<String, Object?>>[
        {'version': 2},
        {'version': 1, 'unsupported': true},
        {'version': 1, 'kind': 'pending'},
        {'version': 1, 'accountId': null},
        {'version': 1, 'from': '2026-02-30'},
        {
          'version': 1,
          'currency': {'code': 'TWD', 'scale': 2},
          'minAbsMinor': '-1',
        },
        {
          'version': 1,
          'currency': {'code': 'TWD', 'scale': 2},
          'maxAbsMinor': '01',
        },
        {'version': 1, 'noteContains': '   '},
      ]) {
        expect(() => LedgerSearchQuery.fromJson(value), throwsFormatException);
      }
    },
  );
}
