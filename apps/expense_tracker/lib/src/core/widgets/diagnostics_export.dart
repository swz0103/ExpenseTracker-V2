import 'dart:async';

import 'package:flutter/material.dart';

import '../design_system/components/buttons.dart';
import '../design_system/feedback.dart';
import '../design_system/keys.dart';
import '../design_system/theme.dart';
import '../diagnostics/error_log.dart';
import '../ledger/persistence/quarantine.dart';
import '../messages/loading_messages.dart';
import '../messages/problem_messages.dart';

/// Saves [text] as a file named [name] where the person chooses; false
/// when they cancel.
typedef SaveText = Future<bool> Function(String name, String text);

/// 匯出診斷: hands the person the diagnostics ([openingReport]: the rows
/// set aside, what kept the book shut, and the error log), saved with
/// [save], and says how it went. The one way of it for every page that
/// cannot reach 設定 › 關於 › 診斷: the held upgrade, the rows set aside,
/// and the lock and welcome views' failure lines (review 31).
Future<void> exportDiagnostics(
  BuildContext context,
  SaveText save, {
  List<QuarantinedRow> rows = const [],
  Object? failure,
}) async {
  try {
    final saved = await save(
      openingReportName,
      openingReport(
        rows: rows,
        // Exception to error words: into the exported diagnostics file,
        // not onto the screen.
        failure: failure == null ? null : ErrorLog.describe(failure),
        log: ErrorLog.instance.text,
      ),
    );
    if (context.mounted && saved) showNote(context, diagnosticsExported);
  } on Object catch (error) {
    ErrorLog.instance.record(diagnosticsExport, error);
    if (context.mounted) showNote(context, describeProblem(error));
  }
}

/// Offers the failure lines under it a way to save the diagnostics
/// ([DiagnosticsButton]); the lock screen, where no settings can be
/// reached, puts one over its views.
class DiagnosticsExport extends InheritedWidget {
  const DiagnosticsExport({
    super.key,
    required this.save,
    required super.child,
  });

  final SaveText save;

  static SaveText? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DiagnosticsExport>()?.save;

  @override
  bool updateShouldNotify(DiagnosticsExport oldWidget) =>
      save != oldWidget.save;
}

/// 匯出診斷 right under a failure line, [problem], that sends the person
/// to the diagnostics (可在診斷匯出詳細資料), where a [DiagnosticsExport]
/// above offers a way to save them; nothing otherwise.
class DiagnosticsButton extends StatelessWidget {
  const DiagnosticsButton(this.problem, {super.key});

  final String? problem;

  /// Whether one shows under [problem] here.
  static bool shows(BuildContext context, String? problem) =>
      problem != null &&
      sendsToDiagnostics(problem) &&
      DiagnosticsExport._of(context) != null;

  @override
  Widget build(BuildContext context) {
    final save = DiagnosticsExport._of(context);
    if (save == null || !shows(context, problem)) {
      return const SizedBox.shrink();
    }
    return TextButton(
      key: Keys.exportDiagnostics,
      style: wordButton(AppColors.muted),
      onPressed: () => unawaited(exportDiagnostics(context, save)),
      child: const Text(diagnosticsExport),
    );
  }
}
