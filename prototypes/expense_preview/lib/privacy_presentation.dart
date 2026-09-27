import 'package:foundation_values/foundation_values.dart';

enum PrivacyMode { visible, hidden }

enum MoneyKind { balance, transaction }

/// Every financial read surface uses the same visual and spoken disclosure rule.
({String text, String label}) presentMoney(
  Money money,
  PrivacyMode mode,
  MoneyKind kind,
) {
  final purpose = kind == MoneyKind.balance ? '帳戶餘額' : '交易金額';
  if (mode == PrivacyMode.hidden) return (text: '••••', label: '$purpose已隱藏');
  final text = '${money.currency.code} ${moneyText(money)}';
  return (text: text, label: '$purpose $text');
}

String moneyText(Money money) => money.majorText;
