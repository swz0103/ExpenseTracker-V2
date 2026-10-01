import 'package:flutter/material.dart';
import 'package:reports/reports.dart';

import 'privacy_presentation.dart';

const warmPaper = Color(0xFFFFFBF5);
const warmSurface = Color(0xFFFFF4E7);
const warmAccent = Color(0xFFC66A3D);
const warmInk = Color(0xFF3D342E);
const warmMuted = Color(0xFF776C64);

/// The first presentation-layer building block. It only reads the report
/// projection; no ledger state or financial invariant is duplicated here.
class WarmMonthOverview extends StatelessWidget {
  const WarmMonthOverview({
    super.key,
    required this.report,
    required this.overflow,
    required this.privacy,
    required this.onDetails,
  });

  final MonthlyReport? report;
  final bool overflow;
  final PrivacyMode privacy;
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    final current = report?.currencies.firstOrNull;
    final month = report?.month;
    final monthLabel = month == null
        ? '本月財務狀況'
        : '${month.year} 年 ${month.month} 月';
    return Semantics(
      container: true,
      label: '本月財務狀況',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  monthLabel,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                onPressed: onDetails,
                tooltip: '查看月收支明細',
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (overflow)
            const Text('本月合計超過可顯示範圍，交易資料仍完整保留。')
          else if (current == null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
              decoration: BoxDecoration(
                color: warmSurface,
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Text('這個月還沒有收支，從下方的「＋」記下第一筆。'),
            )
          else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
              decoration: BoxDecoration(
                color: warmSurface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFF0E1D2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _MonthMetric(
                      label: '收入',
                      value: presentMoney(
                        current.income,
                        privacy,
                        MoneyKind.transaction,
                      ).text,
                      color: const Color(0xFF527C68),
                    ),
                  ),
                  const _WarmDivider(),
                  Expanded(
                    child: _MonthMetric(
                      label: '支出',
                      value: presentMoney(
                        current.expense,
                        privacy,
                        MoneyKind.transaction,
                      ).text,
                      color: const Color(0xFFB65F4A),
                    ),
                  ),
                  const _WarmDivider(),
                  Expanded(
                    child: _MonthMetric(
                      label: '結餘',
                      value: presentMoney(
                        current.net,
                        privacy,
                        MoneyKind.transaction,
                      ).text,
                      color: warmInk,
                    ),
                  ),
                ],
              ),
            ),
            if ((report?.currencies.length ?? 0) > 1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '目前先顯示 ${current.currency.code}；其他幣別可在月收支明細查看。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _WarmDivider extends StatelessWidget {
  const _WarmDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 52,
    margin: const EdgeInsets.symmetric(horizontal: 8),
    color: const Color(0xFFE6D7C8),
  );
}

class _MonthMetric extends StatelessWidget {
  const _MonthMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 7),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          value,
          maxLines: 1,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );
}

class WarmTimelineItem extends StatelessWidget {
  const WarmTimelineItem({
    super.key,
    required this.icon,
    required this.child,
    required this.onTap,
    required this.isLast,
  });

  final IconData icon;
  final Widget child;
  final VoidCallback? onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    label: '查看交易詳情與活動',
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 34,
          child: Column(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(
                  color: Color(0xFFF5DDC8),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 17, color: warmAccent),
              ),
              if (!isLast)
                Container(width: 1, height: 72, color: const Color(0xFFE8D8C8)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: child,
            ),
          ),
        ),
      ],
    ),
  );
}
