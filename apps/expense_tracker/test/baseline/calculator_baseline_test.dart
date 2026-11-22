// The amount calculator and what the compose form refuses: operator
// precedence, rounding of the result, and a zero amount.
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/widgets/amount_keys.dart';
import 'package:expense_tracker/src/features/entries/model/compose_form.dart';
import 'package:flutter_test/flutter_test.dart';

import 'baseline_ledger.dart';

AmountKeys typed(String keys, {bool decimal = false}) {
  final k = AmountKeys('', decimal: decimal);
  for (final key in keys.split(' ')) {
    k.press(key);
  }
  return k;
}

void main() {
  group('evaluate: multiplication and division before + and -', () {
    test('the sum from the calculator\'s own doc: 12+3×4−5÷2', () {
      // 3 x 4 = 12; 5 / 2 = 2.5; 12 + 12 - 2.5 = 21.5.
      expect(evaluate('12+3×4−5÷2'), 21.5);
    });
    test('a product binds tighter than the sum before it', () {
      // 2 + (3 x 4) = 14, not (2 + 3) x 4 = 20.
      expect(evaluate('2+3×4'), 14);
    });
    test('a quotient binds tighter than the difference before it', () {
      // 10 - (4 / 2) = 8, not (10 - 4) / 2 = 3.
      expect(evaluate('10−4÷2'), 8);
    });
    test('equal ranks go left to right', () {
      // (100 / 4) / 5 = 5; (10 - 3) - 2 = 5; 2 x 3 x 4 = 24.
      expect(evaluate('100÷4÷5'), 5);
      expect(evaluate('10−3−2'), 5);
      expect(evaluate('2×3×4'), 24);
    });
    test('a plain number is itself and nothing is zero', () {
      expect(evaluate('12'), 12);
      expect(evaluate(''), 0);
      expect(evaluate('1+2+3'), 6);
    });
    test('an expression that cannot be read gives nothing', () {
      expect(evaluate('5+'), isNull);
      expect(evaluate('+5'), isNull);
      expect(evaluate('5÷0'), isNull);
    });
  });

  group('the keys', () {
    test('the result is rounded to whole dollars', () {
      // 7 / 2 = 3.5 -> 4; 10 / 4 = 2.5 -> 3 (half away from zero).
      expect(typed('7 ÷ 2').result, 4);
      expect(typed('1 0 ÷ 4').result, 3);
      // 10 / 3 = 3.33 -> 3.
      expect(typed('1 0 ÷ 3').result, 3);
    });
    test('a sum left open counts what was typed', () {
      expect(typed('1 2 0 +').result, 120);
    });
    test('the expression is worked out as typed', () {
      final k = typed('2 + 3 × 4');
      expect(k.expression, '2+3×4');
      expect(k.value, 14);
      expect(k.working, isTrue);
      expect(typed('5 0').working, isFalse);
    });
    test('a second operator replaces the first', () {
      expect(typed('5 + −').expression, '5−');
    });
    test('an operator cannot start the expression', () {
      expect(typed('+ 5').expression, '5');
    });
    test('C clears and the back key takes back the last key', () {
      expect(typed('1 2 3 C').expression, '');
      expect(typed('1 2 3 ⌫').expression, '12');
      expect(typed('⌫').expression, '');
    });
    test('a decimal point only where decimals are kept, one to a number', () {
      expect(typed('1 . 5').expression, '15');
      expect(typed('1 . 5 . 2', decimal: true).expression, '1.52');
      expect(typed('.', decimal: true).expression, '0.');
      expect(typed('1 . 5 + 2 . 5', decimal: true).expression, '1.5+2.5');
    });
    test('decimals are kept to two places', () {
      // 0.1 + 0.2 is 0.30000000000000004 as a double; kept to 0.3.
      expect(typed('. 1 + . 2', decimal: true).result, 0.3);
      // 12.5 + 1 = 13.5.
      expect(typed('1 2 . 5 + 1', decimal: true).result, 13.5);
    });
    test('no more than 18 characters are taken', () {
      final k = typed('1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 9');
      expect(k.expression, '123456789012345678');
    });
    test('the amount is capped at 999,999,999 and never negative', () {
      expect(typed('1 0 0 0 0 0 0 0 0 0 0').result, 999999999);
      // 5 - 9 = -4, kept as 0.
      expect(typed('5 − 9').result, 0);
    });
  });

  group('the compose form refuses what has no amount', () {
    Ledger make() => ledgerOf(
      today: day(2026, 10, 4),
      accounts: const [
        Account('bank', '銀行', AccountKind.bank, 100000),
        Account('cash', '現金', AccountKind.cash, 2000),
      ],
      categories: [
        Category('飲食', 'food', 0xFF5C9A83),
        Category('居家', 'home', 0xFF5B8DB0),
      ],
    );

    test('a zero amount is rejected with 請輸入金額', () {
      final form = ComposeForm(make(), type: EntryType.expense);
      expect(form.amount, 0);
      expect(form.problem, '請輸入金額');
    });
    test('a positive amount is accepted', () {
      final form = ComposeForm(make(), type: EntryType.expense)..setAmount(180);
      expect(form.problem, isNull);
      expect(form.build().amount, 180);
    });
    test('income and transfer need an amount as well', () {
      expect(ComposeForm(make(), type: EntryType.income).problem, '請輸入金額');
      expect(ComposeForm(make(), type: EntryType.transfer).problem, '請輸入金額');
    });
    test('a transfer to the same account is rejected', () {
      final form = ComposeForm(make(), type: EntryType.transfer)
        ..setAmount(100)
        ..to = 'bank';
      expect(form.problem, '轉出與轉入不能是同一個帳戶');
    });
    test('a split must add up to the amount, or the gap is told', () {
      final form = ComposeForm(make(), type: EntryType.expense)
        ..setAmount(300)
        ..category = '飲食'
        ..toggleSplit()
        ..setPart(0, 200)
        ..addPart('居家');
      // The new part takes what was left: 200 + 100 = 300, so it is fine.
      expect(form.parts, [('飲食', 200), ('居家', 100)]);
      expect(form.problem, isNull);
      // Lowering the second part to 50 leaves 300 - 250 = 50 unplaced.
      form.setPart(1, 50);
      expect(form.problem, '拆分的金額要等於總額（差 50）');
    });
  });
}
