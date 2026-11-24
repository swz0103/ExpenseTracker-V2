/// How many times larger or smaller than the last one kept a fetched
/// close or exchange rate may be before it is doubted (decision D95).
/// Ten lets through a stock split as large as one for ten, and a capital
/// reduction, and stops a mistyped or garbled figure, such as a close
/// written with extra digits or a rate in the wrong unit.
const doubtfulMoveFactor = 10;

/// Whether [fetched], a close or a rate just fetched, is to be doubted
/// next to [kept], the last one kept for the same stock or currency
/// (D95): not a positive finite number, or more than
/// [doubtfulMoveFactor] times larger or smaller. With nothing kept
/// before (null, or not a positive finite number), only [fetched] itself
/// is looked at.
bool doubtfulMove({required double? kept, required double fetched}) {
  if (!fetched.isFinite || fetched <= 0) return true;
  if (kept == null || !kept.isFinite || kept <= 0) return false;
  return fetched > kept * doubtfulMoveFactor ||
      fetched * doubtfulMoveFactor < kept;
}

/// How many days older than a fetched close or rate the one kept may be
/// before a move past [doubtfulMoveFactor] is taken anyway (D101): after
/// a gap this long a real move (a split larger than one for ten, a
/// redenomination) is likelier than a garbled figure, and the one kept
/// is too old to hold the holdings at.
const doubtfulMoveKeptDays = 30;

/// How far apart, as a share of the first, two fetches in a row may be
/// and still agree (D101): a tenth, a day's limit on TWSE. A figure
/// doubted once and found again within it is the market's, not a slip.
const agreeingFetchesBand = 0.1;

/// Whether [fetched] is taken in place of [kept] (D95, D101): it is a
/// price ([doubtfulMove] would not refuse it alone), and it is within
/// [doubtfulMoveFactor] of what is expected or there is reason to believe
/// the move. Expected is [kept], or, where the book holds splits, stock
/// dividends or capital reductions of the stock after [kept]'s day that
/// multiplied its shares by [reshapedBy], [kept] divided by it: a close
/// far from that, such as one garbled after a split, is doubted all the
/// same (review 18). The reasons: [kept] is more than
/// [doubtfulMoveKeptDays] older ([keptDaysAgo]), or the fetch before was
/// doubted at a figure [fetched] agrees with ([doubtedBefore], within
/// [agreeingFetchesBand]). A figure that is no price is never taken.
bool takesFetched({
  required double? kept,
  required double fetched,
  int? keptDaysAgo,
  double? doubtedBefore,
  double? reshapedBy,
}) {
  if (!fetched.isFinite || fetched <= 0) return false;
  final expected =
      kept != null &&
          reshapedBy != null &&
          reshapedBy.isFinite &&
          reshapedBy > 0
      ? kept / reshapedBy
      : kept;
  if (!doubtfulMove(kept: expected, fetched: fetched)) return true;
  if (keptDaysAgo != null && keptDaysAgo > doubtfulMoveKeptDays) return true;
  if (doubtedBefore == null || !doubtedBefore.isFinite || doubtedBefore <= 0) {
    return false;
  }
  return (fetched - doubtedBefore).abs() <= doubtedBefore * agreeingFetchesBand;
}
