import '../../../core/ledger/ledger.dart';

/// What the form of a recurring item holds while it is filled in: a new
/// item, or the changes to [old]. The screen only shows it.
final class RecurringForm {
  RecurringForm(this.ledger, {this.old})
    : name = old?.name ?? '',
      income = old?.income ?? false,
      amount = old?.amount ?? 0,
      account = old?.account ?? ledger.openAccounts.first.id,
      unit = old?.unit ?? RepeatUnit.month,
      every = old?.every ?? 1,
      end = old?.end,
      active = old?.active ?? true,
      auto = old?.auto ?? false {
    category = old?.category ?? _firstCategory(false);
    start = _firstDay();
  }

  final Ledger ledger;

  /// The item being changed; null for a new one.
  final Recurring? old;

  String name;
  bool income;
  int amount;
  late String category;
  String account;
  RepeatUnit unit;
  int every;
  late DateTime start;
  DateTime? end;
  bool active;

  /// Booked by itself on its day rather than confirmed each time.
  bool auto;

  String _firstCategory(bool income) {
    final choices = ledger.categoriesFor(income: income);
    return choices.isEmpty ? '' : choices.first.name;
  }

  /// When the item starts: as set, or this month on its day for an item
  /// saved before items had a start.
  DateTime _firstDay() {
    final item = old;
    if (item == null) return ledger.today;
    final start = item.start;
    if (start != null) return start;
    final today = ledger.today;
    return DateTime.utc(today.year, today.month, item.day);
  }

  /// The currency of the account it is paid from or into.
  String get currency => ledger.account(account).currency;

  /// Moves between spending and income, with that side's first category.
  void setIncome(bool value) {
    income = value;
    category = _firstCategory(value);
  }

  /// Another account: an amount in another currency means something
  /// else, so it starts again.
  void setAccount(String id) {
    if (ledger.account(id).currency != currency) amount = 0;
    account = id;
  }

  /// One step more or fewer between payments, never below one.
  void step(int by) {
    if (every + by >= 1) every += by;
  }

  /// Paid on day [day] of the month: the start moves to the first such
  /// day on or after it (a 31st waits for a month that has one).
  void setDayOfMonth(int day) {
    for (var k = 0; k < 12; k++) {
      final month = DateTime.utc(start.year, start.month + k);
      final candidate = DateTime.utc(month.year, month.month, day);
      if (candidate.month != month.month) continue;
      if (!candidate.isBefore(start) || k > 0) {
        start = candidate;
        return;
      }
    }
  }

  /// Paid on [weekday] (1 Monday … 7 Sunday): the start moves to the
  /// first such day on or after it.
  void setWeekday(int weekday) {
    final ahead = (weekday - start.weekday) % 7;
    start = DateTime.utc(start.year, start.month, start.day + ahead);
  }

  /// Why the item cannot be saved yet; null when it can.
  String? get problem {
    if (name.trim().isEmpty) return '請輸入名稱';
    if (amount <= 0) return '請輸入金額';
    return null;
  }

  /// The item as the form now stands.
  Recurring build() => Recurring(
    id: old?.id ?? ledger.newId(),
    name: name.trim(),
    amount: amount,
    day: start.day,
    account: account,
    category: category,
    active: active,
    unit: unit,
    every: every,
    start: start,
    end: end,
    income: income,
    merchant: old?.merchant ?? '',
    auto: auto,
  );

  /// How often it comes, such as 每月 5 日.
  String get rhythm => Recurring(
    id: '',
    name: '',
    amount: 0,
    day: start.day,
    account: '',
    category: '',
    unit: unit,
    every: every,
    start: start,
  ).rhythm;

  /// Writes the item to the ledger; false when it cannot be saved.
  bool save() {
    if (problem != null) return false;
    ledger.saveRecurring(build());
    return true;
  }
}
