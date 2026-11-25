import 'package:flutter/material.dart';

import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/navigation/nav.dart';
import '../model/report.dart';
import '../model/report_period.dart';
import '../../../core/widgets/shown_amounts.dart';
import '../../../core/messages/planned_messages.dart';
import 'reports_page_state.dart';

import 'dart:math';

import '../../../core/charts/treemap.dart';
import '../../../../design_system/display/amount.dart';
import 'report_blocks.dart';

/// 財務報表: any stretch of time, not only a month. A month, quarter, year
/// or chosen range: what was left, how income and spending went stretch
/// by stretch, net worth, what the spending was made of against the same
/// time a year before, where it went and under which tags.
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  @override
  State<ReportsPage> createState() => ReportsPageState();
}

/// How the block that gathers the smallest categories looks: named 其他,
/// but a block of its own ([RestShare]), whatever the categories are
/// called.
Category _restBlock() => Category('其他', 'other', AppColors.faint.toARGB32());

/// The report of [period] from the parts of [ledger] it reads.
Report reportOf(Ledger ledger, ReportPeriod period) => Report.of(
  period,
  entries: ledger.entries,
  reports: ledger.reportService,
  balances: ledger.balanceService,
  categories: ledger.categories,
  today: ledger.today,
);

/// The period's 預定 entries, apart from its sums: how many and what they
/// will spend once their days come (D25); null when it has none.
Widget? reportPlannedRow(Ledger ledger, Report report) => report.planned.isEmpty
    ? null
    : TitleRow(
        PlannedText.report(
          report.planned.length,
          ledger.money(report.plannedSpending),
        ),
      );

/// The entries of [period] spent under [name] by today, and how much of
/// them was ([Report.spentUnder]).
(List<Entry>, int) reportSpentUnder(
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

/// The categories of [report] as blocks sized by what they spent, [box]
/// wide. As many of the largest as get a block big enough to read, the
/// rest together: on a small phone or with large text, fewer blocks. A
/// category's block opens [onCategory].
Widget reportTreemap(
  BuildContext context,
  BoxConstraints box,
  Ledger ledger,
  Report report, {
  required ValueChanged<String> onCategory,
}) {
  final names = report.names;
  final expense = report.expense;
  final scale = textGrowth(context);
  final width = box.maxWidth;
  // What a block needs: its name with the share over its amount.
  final minWidth = 84 * scale;
  final minHeight = 56 * scale;
  final base = width * 0.82;
  var height = base;
  var blocks = report.blocks(names.length);
  var rects = <Rect>[];
  // Taller first, then fewer blocks: a category merged into 其他
  // only when no height up to half again more makes room for it.
  search:
  for (var count = min(7, names.length); count >= 1; count--) {
    blocks = report.blocks(count);
    for (final stretch in const [1.0, 1.2, 1.4, 1.6]) {
      height = base * stretch;
      rects = treemapLayout([
        for (final b in blocks) b.amount,
      ], Rect.fromLTWH(0, 0, width, height));
      if (rects.every(
        (r) => r.width - 8 >= minWidth && r.height - 8 >= minHeight,
      )) {
        break search;
      }
    }
  }
  return SizedBox(
    height: height,
    child: Stack(
      children: [
        for (final (i, block) in blocks.indexed)
          if (i < rects.length)
            Positioned.fromRect(
              rect: rects[i].deflate(4),
              child: switch (block) {
                CategoryShare(:final name, :final amount, :final last) =>
                  CategoryBlock(
                    ledger: ledger,
                    category: ledger.category(name),
                    amount: amount,
                    share: percent(amount, expense),
                    change: last == null || last == 0
                        ? null
                        : percent(amount - last, last),
                    large: i == 0,
                    onTap: () => onCategory(name),
                  ),
                // The smallest together: a block of its own, never
                // taken for a category called 其他 (D53).
                RestShare(:final amount) => CategoryBlock(
                  ledger: ledger,
                  category: _restBlock(),
                  amount: amount,
                  share: percent(amount, expense),
                  change: null,
                  large: i == 0,
                  onTap: null,
                ),
              },
            ),
      ],
    ),
  );
}
