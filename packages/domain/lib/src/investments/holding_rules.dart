/// Whether a stock is still held: the one place that decides a holding
/// sold to the last share is no longer one.
library;

/// The state of a stock in the portfolio.
enum HoldingStatus {
  /// Some shares are still held.
  held,

  /// Every share was sold; only its history and realised gain remain.
  soldOut,
}

/// A stock holding [shares] (zero or less once all are sold).
HoldingStatus holdingStatus(int shares) =>
    shares > 0 ? HoldingStatus.held : HoldingStatus.soldOut;
