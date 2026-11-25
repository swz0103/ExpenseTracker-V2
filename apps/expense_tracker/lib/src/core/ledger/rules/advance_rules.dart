/// Where a sum paid for someone (代墊) stands: the one place that decides
/// open, partly settled or settled.
///
/// Lives here until advances have a package of their own
/// (`packages/ledger/advances/rules/`).
library;

/// The state of one advance.
enum AdvanceStatus {
  /// Nothing of it has come back.
  open,

  /// Some of it has come back, some is still owed.
  partlySettled,

  /// All of it has come back.
  settled,
}

/// Where an advance of [amount] stands with [left] of it still owed.
AdvanceStatus advanceStatus({required int amount, required int left}) {
  if (left <= 0) return AdvanceStatus.settled;
  if (left < amount) return AdvanceStatus.partlySettled;
  return AdvanceStatus.open;
}
