import '../ledger/ledger.dart' show Ledger;
import '../../../design_system/display/amount.dart';

/// Amounts as a ledger shows them: dots in place of every figure while
/// its 隱藏金額 switch is on. Each screen asks its own ledger, so two books
/// open at once (as in tests) never share the switch.
extension ShownAmounts on Ledger {
  /// [text], or dots while amounts are hidden.
  String orDots(String text) => amounts.hidden ? '••••' : text;

  /// [groupDigits], or dots while amounts are hidden.
  String money(int value) => orDots(groupDigits(value));

  /// [signed], or dots while amounts are hidden.
  String moneySigned(int value) => orDots(signed(value));

  /// [amountIn], or dots while amounts are hidden.
  String moneyIn(int minor, String currency) =>
      orDots(amountIn(minor, currency));
}
