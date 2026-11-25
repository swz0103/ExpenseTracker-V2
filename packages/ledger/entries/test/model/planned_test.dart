import 'package:ledger_entries/model.dart';
import 'package:ledger_entries/rules.dart';
import 'package:test/test.dart';

void main() {
  final today = DateTime.utc(2026, 11, 24);

  Entry on(DateTime day, {EntryType type = EntryType.expense}) => Entry(
    id: 'e',
    date: day,
    type: type,
    amount: 100,
    account: 'bank',
    holding: type == EntryType.expense ? null : '2330',
    shares: type == EntryType.expense ? 0 : 1,
  );

  test('one year ahead is the limit', () {
    expect(maxDaysAhead, 365);
    // 2026-11-24 + 365 days = 2027-11-24.
    expect(latestEntryDay(today), DateTime.utc(2027, 11, 24));
  });

  test('an entry counts from its own day; until then it is 預定', () {
    expect(countsOn(DateTime.utc(2026, 11, 23), today), isTrue);
    expect(countsOn(today, today), isTrue);
    expect(countsOn(DateTime.utc(2026, 11, 25), today), isFalse);
    expect(isPlanned(on(DateTime.utc(2026, 11, 25)), today), isTrue);
    expect(isPlanned(on(today), today), isFalse);
    final entries = [
      on(DateTime.utc(2026, 11, 1)),
      on(DateTime.utc(2026, 12, 1)),
      on(today),
    ];
    expect(
      [for (final e in countedOn(entries, today)) e.date],
      [DateTime.utc(2026, 11, 1), today],
    );
  });

  test('the write rules keep the limit and keep trades to their day', () {
    List<Type> issues(Entry e) => [
      for (final i in entryIssues(
        e,
        EntryFacts(account: const AccountFacts(AccountKind.bank), today: today),
      ))
        i.runtimeType,
    ];
    expect(issues(on(DateTime.utc(2027, 11, 24))), isEmpty);
    expect(issues(on(DateTime.utc(2027, 11, 25))), [DateTooFarAhead]);
    expect(issues(on(DateTime.utc(2026, 11, 25), type: EntryType.buy)), [
      InvestmentPlanned,
    ]);
    expect(issues(on(today, type: EntryType.buy)), isEmpty);
    // Without the day, as for a record read back, the day is not checked.
    expect(
      entryIssues(
        on(DateTime.utc(2030, 1, 1)),
        const EntryFacts(account: AccountFacts(AccountKind.bank)),
      ),
      isEmpty,
    );
  });

  test('a settlement before archiving may be dated beyond the limit, '
      'through the settled account\'s last day, and nothing else (D121)', () {
    final far = DateTime.utc(2027, 12, 29);
    Entry transfer(DateTime day) => Entry(
      id: 's',
      date: day,
      type: EntryType.transfer,
      amount: 100,
      account: 'ann',
      to: 'bank',
    );
    List<Type> issues(Entry e, {DateTime? settles}) => [
      for (final i in entryIssues(
        e,
        EntryFacts(
          account: const AccountFacts(AccountKind.receivable),
          to: const AccountFacts(AccountKind.bank),
          today: today,
          settlesThrough: settles,
        ),
      ))
        i.runtimeType,
    ];
    // 2026-11-24 + 400 days = 2027-12-29, beyond 2027-11-24.
    expect(issues(transfer(far), settles: far), isEmpty);
    expect(issues(transfer(far)), [DateTooFarAhead]);
    // Not beyond the settled account's last day.
    expect(issues(transfer(DateTime.utc(2027, 12, 30)), settles: far), [
      DateTooFarAhead,
    ]);
    // Only a transfer settles.
    expect(issues(on(far), settles: far), [DateTooFarAhead]);
  });
}
