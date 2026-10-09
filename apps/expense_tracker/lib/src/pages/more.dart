import 'package:flutter/material.dart';

import '../demo/ledger.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import 'nav.dart';

/// 更多: what falls due, then six tools in two columns.
class MorePage extends StatelessWidget {
  const MorePage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  static const _tools = [
    (Pages.reports, '財務報表', Icons.bar_chart, Hue.bank),
    (Pages.investments, '投資與股息', Icons.show_chart, Hue.wallet),
    (Pages.budgets, '預算管理', Icons.pie_chart_outline, Hue.gold),
    (Pages.recurring, '定期交易', Icons.event_repeat_outlined, Hue.card),
    (Pages.categories, '分類管理', Icons.grid_view_outlined, Hue.holdings),
    (Pages.settings, '設定與資料', Icons.tune, Hue.investment),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final due = ledger.due;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            const PageHeader('更多'),
            SoftPanel(
              onTap: () => nav.open(Pages.recurring),
              child: Row(
                children: [
                  const IconBadge(
                    Icons.calendar_month_outlined,
                    Hue.positive,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        due.isEmpty ? '尚無到期項目' : '${due.length} 筆已到期',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '即將到期 ${ledger.upcoming.length} 筆',
                        style: const TextStyle(fontSize: 12, color: Hue.muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.3,
              children: [
                for (final (page, name, icon, color) in _tools)
                  SoftPanel(
                    color: Hue.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    onTap: () => nav.open(page),
                    child: Row(
                      children: [
                        IconBadge(icon, color, size: 32),
                        const SizedBox(width: 10),
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
