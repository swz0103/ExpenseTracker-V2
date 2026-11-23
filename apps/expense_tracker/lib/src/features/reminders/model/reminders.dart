import 'package:flutter/foundation.dart' show Listenable, VoidCallback;

import '../../../../design_system/display/amount.dart';
import '../../../core/ledger/ledger.dart';
import '../../../../design_system/display/date.dart';

/// A day the ledger wants remembered, as a calendar shows it: recurring
/// items falling due and card payments.
final class Reminder {
  const Reminder({
    required this.key,
    required this.day,
    required this.title,
    this.note = '',
    this.daysAhead = 0,
    this.recurring,
    this._bare,
  });

  /// Stable across syncs, so the same reminder is not written twice.
  final String key;

  /// The day it falls on.
  final DateTime day;
  final String title;
  final String note;

  /// How many days before [day] to remind as well.
  final int daysAhead;

  /// The recurring item falling due, which a notification can confirm;
  /// null for a card payment.
  final String? recurring;

  /// [title] without the amount.
  final String? _bare;

  /// This reminder without its amount, for a calendar that should not
  /// show one: 「繳卡費：玉山卡」.
  Reminder get withoutAmount => Reminder(
    key: key,
    day: day,
    title: _bare ?? title,
    note: note,
    daysAhead: daysAhead,
    recurring: recurring,
  );
}

/// The parts of the ledger what falls due is read from, its clock, and
/// its changes to follow: what the calendar and the notifications sync
/// from (docs/adr/0013-models-take-what-they-use.md).
final class ReminderBook implements Listenable {
  ReminderBook({
    required this._changes,
    required this._clock,
    required this.recurring,
    required this.recurringService,
    required this.accounts,
    required this.statementService,
    required this.entries,
    required this.budgets,
    required this.budgetService,
  });

  final Listenable _changes;
  final DateTime Function() _clock;
  final RecurringReader recurring;
  final RecurringService recurringService;
  final AccountReader accounts;
  final StatementService statementService;
  final EntryReader entries;
  final BudgetReader budgets;
  final BudgetService budgetService;

  /// The ledger's today, read each time: a book followed past midnight
  /// moves on with it.
  DateTime get today => _clock();

  @override
  void addListener(VoidCallback listener) => _changes.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _changes.removeListener(listener);

  Account account(String id) => accounts.resolve(id);

  /// What falls due in the next [days] days, soonest first: each unbooked
  /// day of an active recurring item, and each card's payment still owed.
  List<Reminder> reminders({int days = 60}) {
    final last = today.add(Duration(days: days));
    bool ahead(DateTime d) => !d.isBefore(today) && !d.isAfter(last);
    String key(String kind, String id, DateTime d) =>
        '$kind:$id:${d.year}-${d.month}-${d.day}';
    final found = <Reminder>[];
    for (final r in recurring.all) {
      if (!r.active) continue;
      final currency = account(r.account).currency;
      final amount = currency == homeCode
          ? groupDigits(r.amount)
          : '$currency ${plainIn(r.amount, currency)}';
      final booked = recurringService
          .confirmationsIn(r, today.year, today.month)
          .length;
      for (var k = 0; k * 31 <= days + 31; k++) {
        final month = DateTime.utc(today.year, today.month + k);
        final dates = r.datesIn(month.year, month.month);
        for (final d in k == 0 ? dates.skip(booked) : dates) {
          if (!ahead(d)) continue;
          found.add(
            Reminder(
              key: key('r', r.id, d),
              day: d,
              title: '${r.income ? '入帳' : '扣款'}：${r.name} $amount',
              bare: '${r.income ? '入帳' : '扣款'}：${r.name}',
              note: '定期交易，扣款帳戶：${account(r.account).name}',
              recurring: r.id,
            ),
          );
        }
      }
    }
    for (final card in accounts.all) {
      if (card.kind != AccountKind.card || card.archived) continue;
      final (_, end, due) = statementService.statement(card);
      final owed = statementService.statementDue(card);
      if (owed <= 0 || !ahead(due)) continue;
      found.add(
        Reminder(
          key: key('c', card.id, end),
          day: due,
          title: '繳卡費：${card.name} ${groupDigits(owed)}',
          bare: '繳卡費：${card.name}',
          note: '${formatMd(end)} 結帳的帳單',
          daysAhead: 2,
        ),
      );
    }
    return found..sort((a, b) => a.day.compareTo(b.day));
  }
}
