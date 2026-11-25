// DATA FILE: edit the table, not the code around it.
//
// How the Taiwan stock exchanges' days differ from the government office
// calendar (`taiwanCalendarTable` in core). The exchanges are closed on
// every office day off, and in addition:
//
//   * on the weekday days off listed below, which the offices worked;
//   * on every weekend day, make-up workdays (補行上班) included: the
//     exchange's notice for Sat 2025-02-08 reads 「補行上班，但不交易亦
//     不交割」, so such a Saturday is neither a trading nor a settlement
//     day. This is a rule, not a row: `taiwanMarketDays` drops the office
//     calendar's make-up workdays.
//
// Source: 臺灣證券交易所「市場開休市日期」,
//   https://www.twse.com.tw/rwd/zh/holidaySchedule/holidaySchedule?date=20250101&response=json
//   (and date=20260101, date=20270101). Retrieved: 2026-11-23.
// Compared day by day with the office table for 2025 to 2027: the only
// weekday the exchanges closed that the offices worked is 2025-05-01
// (勞動節, an office day off only from 2026); the 2026 and 2027 rows are
// office days off already and are kept so 5/1 stays in one place. The
// days 「市場無交易，僅辦理結算交割作業」 before the Lunar New Year are
// settlement days and are office workdays, so nothing is listed for them.
//
// Not here, because they cannot be known in advance: typhoon and other
// emergency closures.
//
// To add a year: add it to core's office table first, compare the
// exchange's schedule for that year with it, append the differing
// weekdays here and add the year to the `years:` line. A year not listed
// in BOTH tables is not verified, and settlement falls back to weekends
// only and says so.
import 'package:core/foundation_values.dart';

/// The table, one row per line: `date,holiday,name`.
const taiwanMarketClosureTable = '''
years:2025,2026,2027
2025-05-01,holiday,勞動節
2026-05-01,holiday,勞動節
2027-05-01,holiday,勞動節
''';

/// The days the Taiwan stock exchanges trade and settle, as far as is
/// known: the official calendar's weekdays off and
/// [taiwanMarketClosureTable] closed, and no weekend day open, not even a
/// make-up workday.
final taiwanMarketDays = () {
  final closed = taiwanHolidays.closedAlso(
    HolidayCalendar.parse(taiwanMarketClosureTable),
  );
  return HolidayCalendar(
    years: closed.years,
    holidays: closed.holidays,
    workdays: const {},
  );
}();

/// Taiwan stock trades settle this many exchange days after the trade:
/// T+2.
const taiwanSettlementDays = 2;
