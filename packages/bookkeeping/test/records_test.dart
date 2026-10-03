import 'package:bookkeeping/bookkeeping.dart';
import 'package:categories/categories.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:merchants/merchants.dart';
import 'package:tags/tags.dart';
import 'package:test/test.dart';

/// The versioned records stored next to postings: catalog rows, card
/// charges and payments, and investment trades.
void main() {
  final workspace = WorkspaceId(PublicId.generate());
  final twd = Currency.of('TWD');
  final usd = Currency.of('USD');
  Matcher rejected() => throwsA(isA<CodecException>());

  test('catalog rows round trip and refuse unknown fields', () {
    final parent = PublicId.generate();
    final category = Category.restore(
      id: PublicId.generate(),
      workspace: workspace,
      name: '午餐',
      kind: CategoryKind.expense,
      version: 3,
      parentId: parent,
    );
    final read = CatalogCodec.readCategory(CatalogCodec.category(category));
    expect(read.name, '午餐');
    expect(read.parentId, parent);
    expect(read.version, 3);
    final replacement = PublicId.generate();
    final tag = Tag.restore(
      id: PublicId.generate(),
      workspace: workspace,
      name: '旅行',
      version: 2,
      archived: true,
      replacementId: replacement,
    );
    final readTag = CatalogCodec.readTag(CatalogCodec.tag(tag));
    expect(readTag.archived, isTrue);
    expect(readTag.replacementId, replacement);
    final merchant = Merchant.restore(
      id: PublicId.generate(),
      workspace: workspace,
      name: '全聯',
      version: 1,
      aliases: ['PX Mart'],
    );
    final json = CatalogCodec.merchant(merchant);
    expect(CatalogCodec.readMerchant(json).aliases, merchant.aliases);
    expect(() => CatalogCodec.readMerchant({...json, 'extra': 1}), rejected());
    expect(
      () => CatalogCodec.readMerchant({...json, 'version': 2}),
      rejected(),
    );
    expect(
      () => CatalogCodec.readTag({...CatalogCodec.tag(tag), 'archived': 'no'}),
      rejected(),
    );
  });

  test('card charges keep their foreign amount; pending stays pending', () {
    final card = PublicId.generate();
    final pending = CardCharge.pending(
      id: PublicId.generate(),
      workspace: workspace,
      cardId: card,
      kind: CardChargeKind.purchase,
      authorizedOn: BusinessDate(2026, 10, 3),
      authorizedAmount: Money(usd, BigInt.from(1000)),
    );
    final again = CardRecords.readCharge(CardRecords.charge(pending));
    expect(again.isPosted, isFalse);
    expect(again.authorizedAmount, pending.authorizedAmount);
    final posted = pending.post(
      postedOn: BusinessDate(2026, 10, 5),
      settledAmount: Money(twd, BigInt.from(320)),
      fee: Money(twd, BigInt.from(5)),
      ledgerEventId: PublicId.generate(),
    );
    final json = CardRecords.charge(posted);
    final read = CardRecords.readCharge(json);
    expect(read.foreignAmount, Money(usd, BigInt.from(1000)));
    expect(read.ledgerEventId, posted.ledgerEventId);
    expect(read.fee, posted.fee);
    // A pending charge cannot carry posted fields.
    final broken = {
      ...CardRecords.charge(pending),
      'fee': Money(twd, BigInt.zero).toJson(),
    };
    expect(() => CardRecords.readCharge(broken), rejected());
    final payment = CardPayment(
      id: PublicId.generate(),
      workspace: workspace,
      cardId: card,
      statementClose: BusinessDate(2026, 10, 25),
      postedOn: BusinessDate(2026, 11, 8),
      amount: Money(twd, BigInt.from(325)),
      ledgerEventId: PublicId.generate(),
    );
    final paid = CardRecords.readPayment(CardRecords.payment(payment));
    expect(paid.amount, payment.amount);
    expect(paid.statementClose, payment.statementClose);
  });

  test('trade records read back for the history and replay lots', () {
    final account = PublicId.generate();
    final instrument = PublicId.generate();
    final lot = PublicId.generate();
    Map<String, Object?> record(Map<String, Object?> fields) => {
      'version': InvestmentRecords.version,
      'accountId': account.value,
      'instrumentId': instrument.value,
      ...fields,
    };
    final buy = record({
      'kind': 'buy',
      'id': PublicId.generate().value,
      'postingId': PublicId.generate().value,
      'date': '2026-10-01',
      'lotId': lot.value,
      'quantity': '10',
      'unitPrice': '150',
      'gross': Money(usd, BigInt.from(150000)).toJson(),
      'fee': Money(usd, BigInt.zero).toJson(),
      'tax': Money(usd, BigInt.zero).toJson(),
      'cost': Money(usd, BigInt.from(150000)).toJson(),
    });
    final action = record({
      'kind': 'action',
      'id': PublicId.generate().value,
      'postingId': null,
      'date': '2026-10-10',
      'net': Money(usd, BigInt.zero).toJson(),
      'realized': Money(usd, BigInt.zero).toJson(),
      'lots': [
        {
          'lotId': lot.value,
          'units': '${BigInt.from(5) * BigInt.from(10).pow(12)}',
          'remainingCost': Money(usd, BigInt.from(150000)).toJson(),
        },
      ],
    });
    final trade = InvestmentRecords.readTrade(buy);
    expect(trade.kind, 'buy');
    expect(trade.cash, Money(usd, BigInt.from(-150000)));
    expect(trade.quantity.toString(), '10');
    expect(InvestmentRecords.readTrade(action).postingId, isNull);
    final lots = InvestmentRecords.openLots([buy, action]);
    expect(lots.single.remainingQuantity.toString(), '5');
    expect(lots.single.expectedVersion, 2);
    expect(
      () => InvestmentRecords.readTrade({...buy, 'kind': 'gift'}),
      rejected(),
    );
    expect(
      () => InvestmentRecords.openLots([{...buy, 'version': 9}]),
      rejected(),
    );
  });
}
