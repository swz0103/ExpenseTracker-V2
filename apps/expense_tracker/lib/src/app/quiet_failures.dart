import '../core/messages/problem_messages.dart';

/// Tells the person, once a run for each kind, that a step running by
/// itself did not work ([QuietStep]); the step has recorded its error in
/// the ErrorLog, where the note says the details are (D84).
final class QuietFailures {
  QuietFailures(this._say);

  final void Function(String note) _say;

  final _told = <QuietStep>{};

  /// [step] failed: said unless it was already this run.
  void failed(QuietStep step) {
    if (_told.add(step)) _say(step.note);
  }
}
