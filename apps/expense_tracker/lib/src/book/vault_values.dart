part of 'vault_journal.dart';

// Conversions between the screens' plain values and the ledger's.

/// Follows merges from [id] to the row that replaced it.
T? _live<T>(Map<PublicId, T> rows, PublicId id, PublicId? Function(T) next) {
  var row = rows[id];
  for (var hops = 0; row != null && hops < 32; hops++) {
    final replacement = next(row);
    if (replacement == null) return row;
    row = rows[replacement];
  }
  return row;
}

PublicId? _parse(String id) {
  try {
    return PublicId.parse(id);
  } on Object {
    return null;
  }
}

Money _ntd(int amount) => Money(homeCurrency, BigInt.from(amount));

/// [amount] in the smallest unit of [account]'s currency.
Money _in(Account account, int amount) =>
    Money(account.currency, BigInt.from(amount));

/// What a foreign entry [e] in [account] was worth in NT$, which the
/// ledger keeps for reports, budgets and net worth; none for NT$.
Money? _homeOf(Account account, ui.Entry e) {
  if (account.currency == homeCurrency) return null;
  final home = e.home;
  if (home == null || home <= 0) {
    throw const AppFailure(FailureKind.rejected, 'app.home-value');
  }
  return _ntd(home);
}

/// What reached [to] when it is kept in another currency than [from].
Money? _receivedIn(Account from, Account to, ui.Entry e) {
  if (from.currency == to.currency) return null;
  final received = e.received;
  if (received == null || received <= 0) {
    throw const AppFailure(FailureKind.rejected, 'app.received');
  }
  return _in(to, received);
}

/// A transfer's fee is counted as NT$ spending, so only an NT$ account
/// pays one.
void _requireHomeFee(Account from, ui.Entry e) {
  if (e.fee > 0 && from.currency != homeCurrency) {
    throw const AppFailure(FailureKind.rejected, 'app.foreign-fee');
  }
}

int _int(Money money) => money.minorUnits.toInt();

BusinessDate _day(DateTime date) =>
    BusinessDate(date.year, date.month, date.day);

DateTime _date(BusinessDate day) => DateTime.utc(day.year, day.month, day.day);

/// Whole shares in a quantity written as decimal text.
int _whole(Object? quantity) =>
    quantity is String ? int.parse(quantity.split('.').first) : 0;

/// [amount] over [shares] to six decimals: the ledger takes a gross one
/// unit off price times quantity, which this stays within up to two
/// million shares.
String _unitPrice(int amount, int shares) {
  final count = BigInt.from(shares < 1 ? 1 : shares);
  final doubled = BigInt.from(amount) * BigInt.from(2000000) + count;
  final scaled = doubled ~/ (count * BigInt.two);
  final digits = scaled.toString().padLeft(7, '0');
  final whole = digits.substring(0, digits.length - 6);
  final fraction = digits
      .substring(digits.length - 6)
      .replaceAll(RegExp(r'0+$'), '');
  return fraction.isEmpty ? whole : '$whole.$fraction';
}

AccountKind _kind(ui.AccountKind kind) => switch (kind) {
  ui.AccountKind.cash => AccountKind.cash,
  ui.AccountKind.bank => AccountKind.bank,
  ui.AccountKind.wallet => AccountKind.eWallet,
  ui.AccountKind.card => AccountKind.creditCard,
  ui.AccountKind.loan => AccountKind.loan,
  ui.AccountKind.receivable => AccountKind.receivable,
};

ui.AccountKind _uiKind(AccountKind kind) => switch (kind) {
  AccountKind.cash => ui.AccountKind.cash,
  AccountKind.bank || AccountKind.manual => ui.AccountKind.bank,
  AccountKind.eWallet => ui.AccountKind.wallet,
  AccountKind.creditCard => ui.AccountKind.card,
  AccountKind.loan => ui.AccountKind.loan,
  AccountKind.receivable => ui.AccountKind.receivable,
};
