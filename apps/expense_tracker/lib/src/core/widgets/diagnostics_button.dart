import 'dart:async';

import 'package:flutter/material.dart';

import '../design_system/components/buttons.dart';
import '../design_system/keys.dart';
import '../design_system/theme.dart';
import '../messages/diagnostics_messages.dart';
import '../messages/problem_messages.dart';

/// Offers the failure lines under it a way to save the diagnostics
/// ([DiagnosticsButton]): [export] does it, as `exportDiagnostics` from
/// [BuildContext] it is pressed in. The lock screen, where no settings can
/// be reached, puts one over its views (review 31).
class DiagnosticsExport extends InheritedWidget {
  const DiagnosticsExport({
    super.key,
    required this.export,
    required super.child,
  });

  final Future<void> Function(BuildContext context) export;

  static Future<void> Function(BuildContext)? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DiagnosticsExport>()?.export;

  @override
  bool updateShouldNotify(DiagnosticsExport oldWidget) =>
      export != oldWidget.export;
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
    final export = DiagnosticsExport._of(context);
    if (export == null || !shows(context, problem)) {
      return const SizedBox.shrink();
    }
    return TextButton(
      key: Keys.exportDiagnostics,
      style: wordButton(AppColors.muted),
      onPressed: () => unawaited(export(context)),
      child: const Text(diagnosticsExport),
    );
  }
}
