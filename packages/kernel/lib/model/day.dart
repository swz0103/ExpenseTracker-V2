import 'package:core/foundation_values.dart' show BusinessDate, daysInMonth;

/// A calendar day as one number, year × 10000 + month × 100 + day, so
/// days sort as numbers and compare in SQL. Made from a [BusinessDate]
/// and read back as one: the rest of the app keeps days as those.
extension type const Day._(int ymd) implements Object {
  /// The day [date] is.
  Day.of(BusinessDate date)
    : this._(date.year * 10000 + date.month * 100 + date.day);

  /// A day kept as its number, read back from where it was stored.
  const Day.stored(int ymd) : this._(ymd);

  /// Before every record of every book: where what an account or a
  /// holding held from the start is dated, since the records keep no day
  /// for it.
  static const beforeAll = Day._(10101);

  /// After every day of every book: the end of a range with none.
  static const afterAll = Day._(99991231);

  int get year => ymd ~/ 10000;
  int get month => ymd ~/ 100 % 100;
  int get day => ymd % 100;

  /// The month this day falls in, as year × 100 + month: what monthly
  /// sums are kept by.
  int get monthKey => ymd ~/ 100;

  BusinessDate get date => BusinessDate(year, month, day);

  /// The first and the last day of the month this day falls in.
  Day get firstOfMonth => Day._(monthKey * 100 + 1);
  Day get lastOfMonth => Day._(monthKey * 100 + daysInMonth(year, month));

  /// The day before.
  Day get previous => Day.of(date.addDays(-1));

  bool operator <(Day other) => ymd < other.ymd;
  bool operator <=(Day other) => ymd <= other.ymd;
  bool operator >(Day other) => ymd > other.ymd;
  bool operator >=(Day other) => ymd >= other.ymd;
}

/// Where an intent stands in the book: its day, then the order it was
/// first kept in, which an edit keeps.
typedef Position = ({Day date, int seq});

/// Negative when [a] stands before [b], positive after, 0 at the same
/// place.
int comparePositions(Position a, Position b) => a.date.ymd != b.date.ymd
    ? a.date.ymd.compareTo(b.date.ymd)
    : a.seq.compareTo(b.seq);
