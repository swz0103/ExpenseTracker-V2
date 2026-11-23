import 'package:flutter/widgets.dart';

import '../design_system/feedback.dart';
import '../ledger/ledger.dart' show LedgerProblem;
import '../messages/problem_messages.dart';

/// Shows why a command was refused, in words a person can act on, as
/// every other note is shown.
void showProblem(BuildContext context, Object error) =>
    showNote(context, describeProblem(error));

/// Runs [command], a change of the ledger from a button with no form to
/// answer in; a change the ledger refuses is told with [showProblem]
/// rather than going unheard. Whether it went through.
bool refusalShown(BuildContext context, void Function() command) {
  try {
    command();
    return true;
  } on LedgerProblem catch (problem) {
    // A refusal is the person's to hear, not a fault to log.
    context.report(problem);
    return false;
  }
}

extension on BuildContext {
  /// Tells [problem] at the foot of the screen.
  void report(LedgerProblem problem) => showProblem(this, problem);
}
