/// One row of an [AttemptPolicy]: from [failures] wrong secrets in a row
/// on, the next try waits [wait].
final class AttemptStep {
  const AttemptStep({required this.failures, required this.wait});

  /// How many wrong secrets in a row this row starts at.
  final int failures;

  /// How long the next try waits from the last wrong one.
  final Duration wait;
}

/// How wrong passwords and recovery codes are slowed down on the lock
/// screen: the one table of it. A few tries are free, as a slip of the
/// finger is; after them each further wrong one makes the next wait
/// longer, up to the last row, which holds from then on. Nothing is ever
/// erased: the right secret opens the ledger once the wait is over.
///
/// The policy only says how long; counting the tries, keeping the count
/// and reading clocks are the caller's.
final class AttemptPolicy {
  const AttemptPolicy(this.steps);

  /// The rule the lock screen is held to.
  ///
  /// Provisional numbers, waiting for the owner's decision: four free
  /// tries, 30 seconds after the fifth wrong one, then longer with each,
  /// an hour at most.
  static const standard = AttemptPolicy([
    AttemptStep(failures: 5, wait: Duration(seconds: 30)),
    AttemptStep(failures: 6, wait: Duration(minutes: 1)),
    AttemptStep(failures: 7, wait: Duration(minutes: 2)),
    AttemptStep(failures: 8, wait: Duration(minutes: 5)),
    AttemptStep(failures: 9, wait: Duration(minutes: 15)),
    AttemptStep(failures: 10, wait: Duration(minutes: 30)),
    AttemptStep(failures: 11, wait: Duration(hours: 1)),
  ]);

  /// The rows, by rising [AttemptStep.failures].
  final List<AttemptStep> steps;

  /// How long the next try waits after [failures] wrong ones in a row:
  /// the row with the most failures not above [failures], or no wait
  /// below the first row.
  Duration waitAfter(int failures) {
    var wait = Duration.zero;
    for (final step in steps) {
      if (step.failures > failures) break;
      wait = step.wait;
    }
    return wait;
  }
}
