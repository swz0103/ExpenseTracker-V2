import 'package:foundation_values/foundation_values.dart';
import 'package:recurring_transactions/recurring_transactions.dart';
import 'package:test/test.dart';

final _id = PublicId.parse('018f4a28-8080-7a10-8a10-123456789abc');
final _account = PublicId.parse('018f4a28-8080-7a10-8a10-123456789abd');

RecurringTemplate template(
  String first,
  RecurrenceUnit unit, {
  int every = 1,
  int version = 1,
}) => RecurringTemplate(
  id: _id,
  workspace: WorkspaceId(_id),
  accountId: _account,
  label: '房租',
  amount: Money(Currency('TWD', 0), BigInt.from(-100)),
  firstDate: BusinessDate.parse(first),
  unit: unit,
  every: every,
  version: version,
);

List<String> dates(RecurringTemplate plan, String after, String through) =>
    dueCandidates(
      plan,
      after: BusinessDate.parse(after),
      through: BusinessDate.parse(through),
    ).map((candidate) => candidate.dueDate.toString()).toList();

void main() {
  test('monthly anchor recovers after short month', () {
    expect(
      dates(
        template('2024-01-31', RecurrenceUnit.month),
        '2024-01-30',
        '2024-04-30',
      ),
      ['2024-01-31', '2024-02-29', '2024-03-31', '2024-04-30'],
    );
  });

  test('leap-day annual anchor returns on next leap year', () {
    expect(
      dates(
        template('2024-02-29', RecurrenceUnit.year),
        '2024-02-29',
        '2028-02-29',
      ),
      ['2025-02-28', '2026-02-28', '2027-02-28', '2028-02-29'],
    );
  });

  test('every N weeks and months use original anchor', () {
    expect(
      dates(
        template('2025-01-01', RecurrenceUnit.week, every: 2),
        '2025-01-01',
        '2025-02-01',
      ),
      ['2025-01-15', '2025-01-29'],
    );
    expect(
      dates(
        template('2025-01-31', RecurrenceUnit.month, every: 2),
        '2025-01-31',
        '2025-07-31',
      ),
      ['2025-03-31', '2025-05-31', '2025-07-31'],
    );
  });

  test('offline catch-up is exclusive after and stable on retry', () {
    final plan = template('2025-01-01', RecurrenceUnit.day, every: 3);
    final first = dueCandidates(
      plan,
      after: BusinessDate.parse('2025-01-01'),
      through: BusinessDate.parse('2025-01-12'),
    );
    final retry = dueCandidates(
      plan,
      after: BusinessDate.parse('2025-01-01'),
      through: BusinessDate.parse('2025-01-12'),
    );
    expect(first.map((c) => c.dueDate.toString()), [
      '2025-01-04',
      '2025-01-07',
      '2025-01-10',
    ]);
    expect(first.map((c) => c.key), retry.map((c) => c.key));
    expect(first.map((c) => c.key).toSet().length, first.length);
  });

  test('changed template version retains the occurrence deduplication key', () {
    final old = dueCandidates(
      template('2025-01-01', RecurrenceUnit.month),
      after: BusinessDate.parse('2024-12-31'),
      through: BusinessDate.parse('2025-01-01'),
    ).single;
    final revised = dueCandidates(
      template('2025-01-01', RecurrenceUnit.month, version: 2),
      after: BusinessDate.parse('2024-12-31'),
      through: BusinessDate.parse('2025-01-01'),
    ).single;
    expect(old.key, revised.key);
  });

  test('same template ID in another workspace has another key', () {
    final original = template('2025-01-01', RecurrenceUnit.month);
    final other = RecurringTemplate(
      id: original.id,
      workspace: WorkspaceId(_account),
      accountId: original.accountId,
      label: original.label,
      amount: original.amount,
      firstDate: original.firstDate,
      unit: original.unit,
      every: original.every,
    );
    RecurringCandidate first(RecurringTemplate plan) => dueCandidates(
      plan,
      after: BusinessDate.parse('2024-12-31'),
      through: BusinessDate.parse('2025-01-01'),
    ).single;
    expect(first(original).key, isNot(first(other).key));
  });

  test('candidate cap refuses to silently lose catch-up rows', () {
    expect(
      () => dueCandidates(
        template('2025-01-01', RecurrenceUnit.day),
        after: BusinessDate.parse('2024-12-31'),
        through: BusinessDate.parse('2025-01-03'),
        maxCandidates: 2,
      ),
      throwsStateError,
    );
  });

  test('invalid amount and interval fail before scheduling', () {
    expect(
      () => template('2025-01-01', RecurrenceUnit.day, every: 0),
      throwsFormatException,
    );
    expect(
      () => RecurringTemplate(
        id: _id,
        workspace: WorkspaceId(_id),
        accountId: _account,
        label: '房租',
        amount: Money(Currency('TWD', 0), BigInt.zero),
        firstDate: BusinessDate.parse('2025-01-01'),
        unit: RecurrenceUnit.day,
        every: 1,
      ),
      throwsFormatException,
    );
  });
}
