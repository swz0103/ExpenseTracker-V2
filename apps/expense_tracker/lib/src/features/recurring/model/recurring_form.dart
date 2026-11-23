// Exception to models take what they use: the recurring form is the
// page's state, across accounts, categories, entries and commands
// (ADR-0013).

import '../../../../design_system/display/status_messages.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/messages/recurring_messages.dart';
import '../../../../design_system/display/date.dart';
import '../../../core/messages/validation_messages.dart';
import 'recurring_schedule.dart';

/// What the form of a recurring item holds while it is filled in: a new
/// item, or the changes to [old]. The screen only shows it.
final class RecurringForm {
  RecurringForm(this.ledger, {this.old, DateTime? on})
    : name = old?.name ?? '',
      income = old?.income ?? false,
      amount = old?.amount ?? 0,
      account = old?.account ?? ledger.accounts.open.first.id,
      unit = old?.unit ?? RepeatUnit.month,
      every = old?.every ?? 1,
      end = old?.end,
      active = old?.active ?? true,
      auto = old?.auto ?? false {
    category = old?.category ?? _firstCategory(false);
    start = on ?? _firstDay();
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
    final choices = ledger.categories.forEntries(income: income);
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

  /// The categories offered under the card: the usual ones of its side,
  /// with the one chosen first in place of the last when it is not among
  /// them, so the choice is always in sight.
  List<Category> get categoryChoices {
    final usual = usualCategories(
      ledger.categories,
      ledger.entries,
      income: income,
    );
    if (category.isNotEmpty &&
        usual.isNotEmpty &&
        !usual.any((c) => c.name == category)) {
      usual
        ..removeLast()
        ..insert(0, ledger.category(category));
    }
    return usual;
  }

  /// What differs from a new item's defaults, as the strip under the
  /// categories shows it: when it starts, how it is booked, an end and
  /// whether it is paused.
  List<String> get notes => [
    '${formatMd(start)} 起',
    auto ? '到期自動入帳' : '手動入帳',
    if (end case final end?) '到 ${formatMd(end)}',
    if (!active) StatusWords.paused,
  ];

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

  /// Why the item cannot be saved yet; null when it can: the ledger's
  /// write rules, which the save asks again.
  String? get problem {
    final found = recurringIssues(
      amount: amount,
      every: every,
      day: start.day,
      start: start,
      end: end,
    );
    return found.isEmpty ? null : validationMessage(found.first);
  }

  /// The item as the form now stands.
  Recurring build() => Recurring(
    id: old?.id ?? ledger.newId(),
    // Left without a name, it is called by its category.
    name: name.trim().isEmpty ? category : name.trim(),
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
    skipped: old?.skipped ?? const {},
  );

  /// How often it comes, such as 每月 5 日.
  String get rhythm => rhythmOf(
    Recurring(
      id: '',
      name: '',
      amount: 0,
      day: start.day,
      account: '',
      category: '',
      unit: unit,
      every: every,
      start: start,
    ),
  );

  /// Writes the item to the ledger; false when it cannot be saved.
  bool save() {
    if (problem != null) return false;
    ledger.recurringCommands.saveRecurring(build());
    return true;
  }
}
