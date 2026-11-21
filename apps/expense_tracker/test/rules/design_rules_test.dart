import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The date-format rule: dates are written by core/formatting/dates.dart.
/// It reads what strings are built of, so it stays a text match; the
/// design system's other rules (colours, sizes, buttons, retired widgets,
/// corners and gaps, motion, shared words) read the syntax tree, in
/// tooling/architecture_checks (app_syntax_test, app_design_syntax_test).
void main() {
  test(
    'dates are written by core/formatting/dates.dart, not built by hand',
    () {
      final handBuilt = RegExp(
        r'\.(month|year)\}/\$\{|\.month\} 月 \$\{|\.year\} 年 \$\{|'
        r'週\$\{weekdayNames\[\w+\.weekday',
      );
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        if (file.path.endsWith('core/formatting/dates.dart')) continue;
        final lines = file.readAsLinesSync();
        for (final (i, line) in lines.indexed) {
          expect(
            handBuilt.hasMatch(line),
            isFalse,
            reason: '${file.path}:${i + 1} builds a date: use dates.dart',
          );
        }
      }
    },
  );
}
