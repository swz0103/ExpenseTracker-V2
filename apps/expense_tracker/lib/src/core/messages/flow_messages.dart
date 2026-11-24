/// What the pages say where a way on or out is offered (D85): a list with
/// nothing on it, the tour.
abstract final class FlowWords {
  /// 收支紀錄 with nothing written yet (no search, no filter).
  static const noEntriesYet = '還沒有紀錄';

  /// What writes the first one.
  static const addEntry = '記一筆';

  /// 收支紀錄 where the search or the filters leave nothing.
  static const noMatches = '沒有符合篩選的紀錄';

  /// What takes the search and the filters away.
  static const clearFilters = '清除篩選';

  /// Ends the tour at any stop.
  static const skipTour = '略過';
}
