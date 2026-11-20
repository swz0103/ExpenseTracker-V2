import 'package:flutter/widgets.dart';

import '../design_system/feedback.dart';
import '../messages/problem_messages.dart';

/// Shows why a command was refused, in words a person can act on, as
/// every other note is shown.
void showProblem(BuildContext context, Object error) =>
    showNote(context, describeProblem(error));
