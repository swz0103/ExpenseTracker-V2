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
