import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/entries/forms/trade_cards.dart';
import 'package:flutter_test/flutter_test.dart';

Holding _h(String code, String name) =>
    Holding(code, name, shares: 0, price: 0, cost: 0, change: 0);

void main() {
  test('a holding is called by its name, the fund house left off', () {
    expect(shortHoldingName(_h('2330', '台積電')), '台積電');
    expect(shortHoldingName(_h('0050', '元大台灣50')), '台灣50');
    expect(shortHoldingName(_h('00878', '國泰永續高股息')), '永續高股');
  });

  test('a company keeps the name it shares with a fund house', () {
    // 中信金 once read 金: only funds, codes from 00, lose their house.
    expect(shortHoldingName(_h('2891', '中信金')), '中信金');
    expect(shortHoldingName(_h('2881', '富邦金')), '富邦金');
    expect(shortHoldingName(_h('006208', '富邦台50')), '台50');
  });

  test('a holding whose name is not known has no short name', () {
    // Not its code cut short: 00878 once read 0087 under its own code.
    expect(shortHoldingName(_h('00878', '00878')), '');
    expect(shortHoldingName(_h('2330', '')), '');
  });
}
