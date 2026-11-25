import 'package:flutter/material.dart';

import '../design_system/feedback.dart';
import '../diagnostics/error_log.dart';
import '../ledger/persistence/quarantine.dart';
import '../messages/diagnostics_messages.dart';
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
