import 'package:foundation_values/foundation_values.dart';

enum RecurrenceUnit { day, week, month, year }

/// A fixed-amount proposal. It never posts to the Ledger by itself.
final class RecurringTemplate {
  RecurringTemplate({
    required this.id,
    required this.workspace,
    required this.accountId,
    required this.label,
    required this.amount,
    required this.firstDate,
    required this.unit,
    required this.every,
    this.version = 1,
  }) {
    if (label.trim().isEmpty ||
        label != label.trim() ||
        label.runes.length > 120 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(label) ||
        every < 1 ||
        every > 999 ||
        version < 1 ||
        amount.minorUnits == BigInt.zero) {
      throw const FormatException('Invalid recurring template');
    }
  }

  final PublicId id;
  final WorkspaceId workspace;
  final PublicId accountId;
  final String label;
  final Money amount;
  final BusinessDate firstDate;
  final RecurrenceUnit unit;
  final int every;
  final int version;
}

final class RecurringCandidate {
  const RecurringCandidate({required this.template, required this.dueDate});

  final RecurringTemplate template;
  final BusinessDate dueDate;

  /// A revision cannot turn a previously confirmed date into a second posting.
  String get key =>
      '${template.workspace.id.value}:${template.id.value}:$dueDate';
}

/// Finds due proposals after the last reviewed day, inclusive of [through].
/// A finite cap fails loudly so a long offline interval cannot silently omit
/// candidates. The caller must review and confirm each proposal before posting.
List<RecurringCandidate> dueCandidates(
  RecurringTemplate template, {
  required BusinessDate after,
  required BusinessDate through,
  int maxCandidates = 5000,
}) {
  if (maxCandidates < 1) {
    throw const FormatException('Invalid candidate limit');
  }
  if (through.compareTo(after) <= 0 ||
      through.compareTo(template.firstDate) < 0) {
    return const [];
  }

  var index = _initialIndex(template, after);
  final result = <RecurringCandidate>[];
  while (true) {
    final date = _occurrence(template, index);
    if (date == null || date.compareTo(through) > 0) break;
    if (date.compareTo(after) > 0) {
      if (result.length == maxCandidates) {
        throw StateError('Candidate limit exceeded');
      }
      result.add(RecurringCandidate(template: template, dueDate: date));
    }
    index++;
  }
  return List.unmodifiable(result);
}

/// Confirms a selected day belongs to the current template without scanning
/// every occurrence since its start date.
bool isScheduledDate(RecurringTemplate template, BusinessDate date) {
  if (date.compareTo(template.firstDate) < 0) return false;
  return _occurrence(template, _initialIndex(template, date)) == date;
}

int _initialIndex(RecurringTemplate template, BusinessDate after) {
  if (after.compareTo(template.firstDate) < 0) return 0;
  final first = template.firstDate;
  switch (template.unit) {
    case RecurrenceUnit.day:
    case RecurrenceUnit.week:
      final days = DateTime.utc(
        after.year,
        after.month,
        after.day,
      ).difference(DateTime.utc(first.year, first.month, first.day)).inDays;
      final interval =
          template.every * (template.unit == RecurrenceUnit.week ? 7 : 1);
      return days ~/ interval;
    case RecurrenceUnit.month:
      return ((after.year - first.year) * 12 + after.month - first.month) ~/
          template.every;
    case RecurrenceUnit.year:
      return (after.year - first.year) ~/ template.every;
  }
}

BusinessDate? _occurrence(RecurringTemplate template, int index) {
  final first = template.firstDate;
  final steps = index * template.every;
  switch (template.unit) {
    case RecurrenceUnit.day:
    case RecurrenceUnit.week:
      final days = steps * (template.unit == RecurrenceUnit.week ? 7 : 1);
      final date = DateTime.utc(
        first.year,
        first.month,
        first.day,
      ).add(Duration(days: days));
      if (date.year > 9999) return null;
      return BusinessDate(date.year, date.month, date.day);
    case RecurrenceUnit.month:
      final monthIndex = (first.year - 1) * 12 + first.month - 1 + steps;
      final year = monthIndex ~/ 12 + 1;
      if (year > 9999) return null;
      final month = monthIndex % 12 + 1;
      return BusinessDate(year, month, _clampDay(year, month, first.day));
    case RecurrenceUnit.year:
      final year = first.year + steps;
      if (year > 9999) return null;
      return BusinessDate(
        year,
        first.month,
        _clampDay(year, first.month, first.day),
      );
  }
}

int _clampDay(int year, int month, int anchorDay) {
  final lastDay = DateTime.utc(year, month + 1, 0).day;
  return anchorDay < lastDay ? anchorDay : lastDay;
}
