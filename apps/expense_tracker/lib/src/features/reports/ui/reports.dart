import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/charts/donut.dart';
import '../../../core/charts/treemap.dart';

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

import '../../../core/charts/period_charts.dart';
import '../../../core/text/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/ui/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/nav.dart';
import '../../../core/ui/entry_tile.dart';
import 'compare_section.dart';
import 'report_period.dart';
import '../../../core/ui/shown_amounts.dart';
import '../../../core/diagnostics/error_log.dart';
import '../../../core/text/dates.dart';

part 'report_figures.dart';
part 'report_blocks.dart';
part 'reports_page_state.dart';
part 'reports_habits.dart';

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
