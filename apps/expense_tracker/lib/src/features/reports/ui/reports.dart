import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/charts/treemap.dart';

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

import '../../../core/charts/period_charts.dart';
import '../../../../design_system/display/amount.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/navigation/nav.dart';
import '../../../core/widgets/entry_tile.dart';
import 'compare_section.dart';
import '../model/report.dart';
import '../model/report_period.dart';
import 'report_blocks.dart';
import 'report_habits.dart';
import '../../../core/widgets/shown_amounts.dart';
import '../../../core/diagnostics/error_log.dart';
import '../../../../design_system/display/date.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/formatting/words.dart';
import '../../../core/messages/planned_messages.dart';
import '../../../core/messages/problem_messages.dart';

part 'reports_page_state.dart';

/// 財務報表: any stretch of time, not only a month. A month, quarter, year
/// or chosen range: what was left, how income and spending went stretch
/// by stretch, net worth, what the spending was made of against the same
/// time a year before, where it went and under which tags.
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

/// How the block that gathers the smallest categories looks: named 其他,
/// but a block of its own ([RestShare]), whatever the categories are
/// called.
Category _restBlock() => Category('其他', 'other', AppColors.faint.toARGB32());

/// The report of [period] from the parts of [ledger] it reads.
Report _reportOf(Ledger ledger, ReportPeriod period) => Report.of(
  period,
  entries: ledger.entries,
  reports: ledger.reportService,
  balances: ledger.balanceService,
  categories: ledger.categories,
  today: ledger.today,
);

/// The period's 預定 entries, apart from its sums: how many and what they
/// will spend once their days come (D25); null when it has none.
Widget? _plannedRow(Ledger ledger, Report report) => report.planned.isEmpty
    ? null
    : TitleRow(
        PlannedText.report(
          report.planned.length,
          ledger.money(report.plannedSpending),
        ),
      );

/// The entries of [period] spent under [name] by today, and how much of
/// them was ([Report.spentUnder]).
(List<Entry>, int) _spentUnder(
  Ledger ledger,
  String name,
  ReportPeriod period,
) => Report.spentUnder(
  name,
  ledger.entries,
  period,
  ledger.today,
  ledger.categories,
);
