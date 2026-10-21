import 'package:core/foundation_values.dart';

enum CreditCardError { invalidInput }

final class CreditCardException implements Exception {
  const CreditCardException(this.code);
  final CreditCardError code;
  @override
  String toString() => 'CreditCardException(${code.name})';
}

/// Billing days that applied until a change took effect.
final class CardScheduleChange {
  CardScheduleChange({
    required this.until,
    required this.closingDay,
    required this.dueDay,
  }) {
    _checkDays(closingDay, dueDay);
  }

  /// The first close on the newer days; these days applied before it.
  final BusinessDate until;
  final int closingDay;
  final int dueDay;
}

/// The issuer's actual dates for one statement, when they differ from the
/// schedule.
final class CardCycleOverride {
  CardCycleOverride({
    required this.scheduledClose,
    required this.closesOn,
    required this.dueOn,
  }) {
    final shift = _utc(closesOn).difference(_utc(scheduledClose)).inDays.abs();
    if (shift > 7 || closesOn.compareTo(dueOn) >= 0) {
      throw const CreditCardException(CreditCardError.invalidInput);
    }
  }

  final BusinessDate scheduledClose;
  final BusinessDate closesOn;
  final BusinessDate dueOn;
}

/// A card's billing days over time and the issuer's moved closes: which
/// statement a day falls in, when it closes and when it is due. The ledger
/// and the screens both ask this.
final class CardSchedule {
  CardSchedule({
    required this.closingDay,
    required this.dueDay,
    List<CardScheduleChange> history = const [],
    List<CardCycleOverride> overrides = const [],
  }) : history = List.unmodifiable(history),
       overrides = List.unmodifiable(overrides) {
    _checkDays(closingDay, dueDay);
    for (final (i, change) in this.history.indexed) {
      final until = change.until;
      // A change takes effect on a close of the newer closing day.
      final newer = i + 1 < this.history.length
          ? this.history[i + 1].closingDay
          : closingDay;
      final earlier = i == 0 ? null : this.history[i - 1].until;
      if (until != _day(until.year, until.month, newer) ||
          (earlier != null && until.compareTo(earlier) <= 0)) {
        throw const CreditCardException(CreditCardError.invalidInput);
      }
    }
    final scheduled = <BusinessDate>{};
    for (final override in this.overrides) {
      if (!scheduled.add(override.scheduledClose) ||
          _nominalClose(override.scheduledClose) != override.scheduledClose) {
        throw const CreditCardException(CreditCardError.invalidInput);
      }
    }
  }

  /// The billing days in effect now, since the last [history] change.
  final int closingDay;
  final int dueDay;

  /// Earlier billing days, oldest first, so past statements keep their
  /// dates after a change.
  final List<CardScheduleChange> history;
  final List<CardCycleOverride> overrides;

  /// The statement cycle containing [date], with the billing days in
  /// effect then and any actual dates the issuer used. A statement closes
  /// at the end of its day.
  CardCycle cycleFor(BusinessDate date) {
    final closes = _closesAround(date);
    final actual = [for (final close in closes) datesOf(close)];
    for (var i = 1; i < closes.length; i++) {
      if (date.compareTo(actual[i].$1) <= 0) {
        return CardCycle(
          startsAfter: actual[i - 1].$1,
          closesOn: actual[i].$1,
          dueOn: actual[i].$2,
          scheduledStartsAfter: closes[i - 1],
          scheduledClose: closes[i],
        );
      }
    }
    throw const CreditCardException(CreditCardError.invalidInput);
  }

  /// The last statement close on or before [date].
  BusinessDate lastCloseOn(BusinessDate date) {
    final cycle = cycleFor(date);
    return date == cycle.closesOn ? cycle.closesOn : cycle.startsAfter;
  }

  /// When the statement scheduled to close on [scheduledClose] actually
  /// closes and is due.
  (BusinessDate, BusinessDate) datesOf(BusinessDate scheduledClose) {
    for (final override in overrides) {
      if (override.scheduledClose == scheduledClose) {
        return (override.closesOn, override.dueOn);
      }
    }
    // Due on the first due day after the close: the same month when the
    // due day comes later in it, otherwise the next.
    final close = scheduledClose;
    final (_, dueDay) = _daysOn(close);
    var due = _day(close.year, close.month, dueDay);
    if (due.compareTo(close) <= 0) {
      final following = _month(close.year, close.month, 1);
      due = _day(following.$1, following.$2, dueDay);
    }
    return (close, due);
  }

  /// Scheduled closes from three months before [date] to three after.
  List<BusinessDate> _closesAround(BusinessDate date) {
    final closes = <BusinessDate>[];
    for (var offset = -3; offset <= 3; offset++) {
      final (year, month) = _month(date.year, date.month, offset);
      final days = {...history.map((h) => h.closingDay), closingDay};
      final found = <BusinessDate>{
        for (final day in days)
          if (_daysOn(_day(year, month, day)).$1 == day) _day(year, month, day),
      };
      closes.addAll(found.toList()..sort());
    }
    return closes;
  }

  /// The closing day in effect on [date].
  int closingDayOn(BusinessDate date) => _daysOn(date).$1;

  BusinessDate _nominalClose(BusinessDate date) {
    final (closing, _) = _daysOn(date);
    return _day(date.year, date.month, closing);
  }

  (int, int) _daysOn(BusinessDate date) {
    for (final change in history) {
      if (date.compareTo(change.until) < 0) {
        return (change.closingDay, change.dueDay);
      }
    }
    return (closingDay, dueDay);
  }
}

void _checkDays(int closingDay, int dueDay) {
  if (closingDay < 1 || closingDay > 31 || dueDay < 1 || dueDay > 31) {
    throw const CreditCardException(CreditCardError.invalidInput);
  }
}

DateTime _utc(BusinessDate date) =>
    DateTime.utc(date.year, date.month, date.day);

/// One statement period. The scheduled dates are the nominal ones the
/// card's billing days give; installments are billed by them.
final class CardCycle {
  CardCycle({
    required this.startsAfter,
    required this.closesOn,
    required this.dueOn,
    BusinessDate? scheduledStartsAfter,
    BusinessDate? scheduledClose,
  }) : scheduledStartsAfter = scheduledStartsAfter ?? startsAfter,
       scheduledClose = scheduledClose ?? closesOn {
    if (startsAfter.compareTo(closesOn) >= 0 ||
        closesOn.compareTo(dueOn) >= 0 ||
        this.scheduledStartsAfter.compareTo(this.scheduledClose) >= 0) {
      throw const CreditCardException(CreditCardError.invalidInput);
    }
  }

  final BusinessDate startsAfter;
  final BusinessDate closesOn;
  final BusinessDate dueOn;
  final BusinessDate scheduledStartsAfter;
  final BusinessDate scheduledClose;

  bool includes(BusinessDate postedOn) =>
      postedOn.compareTo(startsAfter) > 0 && postedOn.compareTo(closesOn) <= 0;

  /// Whether an installment scheduled to close on [close] is billed here.
  bool bills(BusinessDate close) =>
      close.compareTo(scheduledStartsAfter) > 0 &&
      close.compareTo(scheduledClose) <= 0;
}

(int, int) _month(int year, int month, int offset) {
  final result = DateTime.utc(year, month + offset, 1);
  if (result.year < 1 || result.year > 9999) {
    throw const CreditCardException(CreditCardError.invalidInput);
  }
  return (result.year, result.month);
}

BusinessDate _day(int year, int month, int requested) {
  final last = DateTime.utc(year, month + 1, 0).day;
  return BusinessDate(year, month, requested > last ? last : requested);
}
