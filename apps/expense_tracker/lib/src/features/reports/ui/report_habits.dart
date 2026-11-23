import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/charts/donut.dart';

import '../../../../design_system/display/amount.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/widgets/shown_amounts.dart';
import '../../../../design_system/display/date.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/formatting/words.dart';
import '../model/report.dart';
import 'report_blocks.dart';

// 習慣: where the money goes most, on which days, and under which tags.

/// 習慣's two highlights: the day of the week spent most on, and the
/// merchant gone to most.
List<Widget> highlightsSection(Ledger ledger, Report report) {
  final days = report.weekdays;
  final most = days.fold(0, max);
  final merchant = report.merchants.isEmpty ? null : report.merchants.first;
  if (most <= 0 && merchant == null) return const [];
  return [
    CardGrid(gap: 10, [
      ReportBlock(
        glyph: Glyph.calendar,
        color: AppColors.negative,
        label: '花最多的一天',
        value: most <= 0 ? '—' : '週${weekdayNames[days.indexOf(most)]}',
        sub: most <= 0 ? '' : '這段時間共 ${ledger.orDots(groupDigits(most))}',
      ),
      ReportBlock(
        glyph: Glyph.store,
        color: AppColors.positive,
        label: '最常去',
        value: merchant?.$1 ?? '—',
        sub: merchant == null
            ? ''
            : '${countOf(merchant.$2, CountUnit.times)} · 每次約 '
                  '${ledger.orDots(groupDigits(divideRounded(merchant.$3, merchant.$2)))}',
      ),
    ]),
  ];
}

/// 常去商家: the merchants gone to most, as a donut beside a list of how
/// often each was gone to and how much each time.
List<Widget> merchantsSection(Ledger ledger, Report report) {
  final rows = report.merchants.take(4).toList();
  if (rows.isEmpty) return const [];
  final total = rows.fold(0, (sum, r) => sum + r.$3);
  return [
    TitleRow(
      '常去商家',
      trailing: Text(
        '這 ${rows.length} 家 · 合計 ${ledger.orDots(groupDigits(total))}',
        style: mutedSmall,
      ),
    ),
    Container(
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s4,
        Space.s4,
        Space.s4,
      ),
      decoration: BoxDecoration(
        color: AppColors.group,
        borderRadius: BorderRadius.circular(Radii.largeIncreased),
      ),
      child: Row(
        children: [
          Donut(
            size: 96,
            thickness: 20,
            slices: [
              for (final (i, r) in rows.indexed)
                (r.$3, AppColors.shades[(i + 2) % AppColors.shades.length]),
            ],
          ),
          const SizedBox(width: Space.s4),
          Expanded(
            child: Column(
              children: [
                for (final (i, (name, count, amount)) in rows.indexed)
                  _merchantRow(ledger, i, name, count, amount),
              ],
            ),
          ),
        ],
      ),
    ),
  ];
}

/// The [i]th merchant of 常去商家: its colour beside the donut's, its
/// name, how often it was gone to and how much each time, and its total.
Widget _merchantRow(Ledger ledger, int i, String name, int count, int amount) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: Space.s1),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.shades[(i + 2) % AppColors.shades.length],
                borderRadius: BorderRadius.circular(Radii.extraSmall),
              ),
            ),
          ),
          const SizedBox(width: Space.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  '${countOf(count, CountUnit.times)} · 每次約 '
                  '${ledger.orDots(groupDigits(divideRounded(amount, count)))}',
                  style: mutedCaption,
                ),
              ],
            ),
          ),
          Text(
            ledger.orDots(groupDigits(amount)),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );

/// 星期: what was spent on each day of the week over the period, the
/// heaviest day in the spending colour.
List<Widget> weekdaysSection(Report report) {
  final days = report.weekdays;
  final most = days.fold(0, max);
  if (most <= 0) return const [];
  final heaviest = days.indexOf(most);
  return [
    TitleRow('星期', trailing: const Text('虛線是每天平均', style: mutedSmall)),
    GroupBox(
      padding: const EdgeInsets.fromLTRB(
        Space.s2,
        Space.s4,
        Space.s2,
        Space.s2,
      ),
      child: Column(
        children: [
          SizedBox(
            height: 96,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final (i, spent) in days.indexed)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.s2,
                            ),
                            child: FractionallySizedBox(
                              heightFactor: spent <= 0
                                  ? 0.03
                                  : max(spent / most, 0.06),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: i == heaviest
                                      ? markOf(AppColors.negative)
                                      : softOf(markOf(AppColors.negative)),
                                  borderRadius: BorderRadius.circular(
                                    Radii.small,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 96 * (days.fold(0, (s, d) => s + d) / 7 / most),
                  child: CustomPaint(
                    size: const Size(double.infinity, 1),
                    painter: DashesPainter(AppColors.muted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.s2),
          Row(
            children: [
              for (final (i, name) in weekdayNames.indexed)
                Expanded(child: _weekdayName(name, peak: i == heaviest)),
            ],
          ),
        ],
      ),
    ),
  ];
}

/// A weekday's name under its bar, red and bold on the heaviest day.
Widget _weekdayName(String name, {required bool peak}) => Text(
  name,
  textAlign: TextAlign.center,
  style: TextStyle(
    fontSize: TextSize.caption,
    fontWeight: peak ? FontWeight.w700 : FontWeight.w500,
    color: peak ? AppColors.negative : AppColors.muted,
  ),
);

List<Widget> tagsSection(Ledger ledger, Report report) {
  final rows = report.tags;
  if (rows.isEmpty) return const [];
  final counts = {
    for (final (tag, n, _) in ledger.reportService.tagStats) tag: n,
  };
  return [
    const TitleRow(Words.tag),
    CardGrid(columns: 3, gap: 8, [
      for (final (tag, amount) in rows.take(9))
        ColorCard(
          color: nameColor(tag),
          radius: Radii.large,
          padding: const EdgeInsets.fromLTRB(
            Space.s3,
            Space.s2,
            Space.s2,
            Space.s2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '#$tag',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: deepOf(nameColor(tag)),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  ledger.orDots(groupDigits(amount)),
                  style: const TextStyle(
                    fontSize: TextSize.heading,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (counts[tag] case final n?)
                Text(countOf(n, CountUnit.entries), style: mutedCaption),
            ],
          ),
        ),
    ]),
  ];
}
