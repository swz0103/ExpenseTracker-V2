// Exception to the radius scale: the home-screen widget matches the
// corners Android draws its widgets with, not the app's own scale.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/design_system/theme.dart' show Hue;
import '../../../core/design_system/widget_hue.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/formatting/dates.dart';
import '../../../core/formatting/words.dart';
import '../../../core/formatting/json_fields.dart';

/// What the widget shows with no figures chosen, as SummaryWidget.kt does.
const _empty = <String, Object?>{
  'title': '記帳本',
  'figure': '本月概況',
  'detail': '到 設定 › 外觀 選擇要顯示的數字',
};

TextStyle _text(double size, Color color) => TextStyle(
  fontSize: size,
  fontWeight: FontWeight.w700,
  color: color,
  height: 1.15,
  decoration: TextDecoration.none,
  fontFeatures: const [FontFeature.tabularFigures()],
);

/// 本月概況 at full size: the month over its budget bar, this week day by
/// day, and 支出 and 收入 at the foot. Without callbacks it is a picture.
class WidgetFace extends StatelessWidget {
  const WidgetFace({
    super.key,
    required this.snapshot,
    this.onOpen,
    this.onExpense,
    this.onIncome,
  });

  final Map<String, Object?>? snapshot;
  final VoidCallback? onOpen;
  final VoidCallback? onExpense;
  final VoidCallback? onIncome;

  @override
  Widget build(BuildContext context) {
    final shown = JsonFields(snapshot ?? _empty);
    final budget = shown.text('budget') ?? '';
    final detail = shown.text('detail') ?? '';
    final week = shown.wholes('week');
    final weekTotal = shown.text('weekTotal') ?? '';
    return _Card(
      radius: 26,
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s4,
        Space.s4,
        Space.s2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: onOpen,
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        shown.text('title') ?? '',
                        maxLines: 1,
                        style: _text(11, WidgetLook.muted),
                      ),
                    ),
                    Text(
                      shown.text('figure') ?? '',
                      maxLines: 1,
                      style: _text(24, WidgetLook.ink),
                    ),
                  ],
                ),
                _BudgetBar(snapshot: shown, height: 8, top: 6),
                const SizedBox(height: Space.s1),
                Row(
                  children: [
                    Expanded(
                      child: Text(budget, style: _text(10.5, WidgetLook.muted)),
                    ),
                    Flexible(
                      child: Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _text(10.5, WidgetLook.muted),
                      ),
                    ),
                  ],
                ),
                if (week != null && week.length == 7) ...[
                  const SizedBox(height: Space.s2),
                  _Week(
                    week: week,
                    total: weekTotal,
                    today: shown.whole('today') ?? -1,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.s2),
          SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: _Half(
                    label: Words.expense,
                    mark: '−',
                    color: WidgetLook.expense,
                    tint: WidgetLook.expenseTint,
                    onTap: onExpense,
                  ),
                ),
                const SizedBox(width: Space.s2),
                Expanded(
                  child: _Half(
                    label: Words.income,
                    mark: '＋',
                    color: WidgetLook.income,
                    tint: WidgetLook.incomeTint,
                    onTap: onIncome,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 本月概況 one row high: what is left of the budget over its bar, and
/// round − and ＋.
class WidgetRow extends StatelessWidget {
  const WidgetRow({
    super.key,
    required this.snapshot,
    this.onOpen,
    this.onExpense,
    this.onIncome,
  });

  final Map<String, Object?>? snapshot;
  final VoidCallback? onOpen;
  final VoidCallback? onExpense;
  final VoidCallback? onIncome;

  @override
  Widget build(BuildContext context) {
    final shown = JsonFields(snapshot ?? _empty);
    return _Card(
      radius: 31,
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s3,
        Space.s2,
        Space.s3,
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onOpen,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    shown.text('shortLabel') ?? shown.text('title') ?? '',
                    maxLines: 1,
                    style: _text(10.5, WidgetLook.muted),
                  ),
                  Text(
                    shown.text('shortFigure') ?? shown.text('figure') ?? '',
                    maxLines: 1,
                    style: _text(16, WidgetLook.ink),
                  ),
                  _BudgetBar(snapshot: shown, height: 6, top: 4),
                ],
              ),
            ),
          ),
          const SizedBox(width: Space.s2),
          _Round(
            mark: '−',
            label: '記支出',
            color: WidgetLook.expense,
            onTap: onExpense,
          ),
          const SizedBox(width: Space.s2),
          _Round(
            mark: '＋',
            label: '記收入',
            color: WidgetLook.income,
            onTap: onIncome,
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.radius,
    required this.padding,
    required this.child,
  });

  final double radius;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: WidgetLook.card,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(color: Hue.float, blurRadius: 18, offset: Offset(0, 6)),
        ],
      ),
      // Merged, not replaced: the app's fonts (Chinese among them) stay.
      child: DefaultTextStyle.merge(
        style: const TextStyle(decoration: TextDecoration.none),
        child: child,
      ),
    );
  }
}

/// The share of the budget used, and a gold mark at how far through the
/// month today is.
class _BudgetBar extends StatelessWidget {
  const _BudgetBar({
    required this.snapshot,
    required this.height,
    required this.top,
  });

  final JsonFields snapshot;
  final double height;
  final double top;

  @override
  Widget build(BuildContext context) {
    final progress = snapshot.whole('progress');
    if (progress == null) return const SizedBox.shrink();
    final pace = snapshot.whole('pace');
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth;
            final round = BorderRadius.circular(height / 2);
            return Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: WidgetLook.track,
                      borderRadius: round,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: width * progress.clamp(0, 100) / 100,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: WidgetLook.accent,
                      borderRadius: round,
                    ),
                  ),
                ),
                if (pace != null && pace > 0)
                  Positioned(
                    left: math.max(0.0, width * pace.clamp(0, 100) / 100 - 2),
                    top: 0,
                    bottom: 0,
                    width: 2,
                    child: const ColoredBox(color: WidgetLook.pace),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 本週: a bar a day, today's in the accent; days still to come a dot.
class _Week extends StatelessWidget {
  const _Week({required this.week, required this.total, required this.today});

  final List<int> week;
  final String total;
  final int today;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('本週', style: _text(11, WidgetLook.muted))),
            if (total.isNotEmpty) Text(total, style: _text(11, WidgetLook.ink)),
          ],
        ),
        const SizedBox(height: Space.s1),
        SizedBox(
          height: 40,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.s1),
                    child: week[i] < 0
                        ? const Align(
                            alignment: Alignment.bottomCenter,
                            child: SizedBox.square(
                              dimension: 4,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: WidgetLook.dot,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          )
                        : FractionallySizedBox(
                            alignment: Alignment.bottomCenter,
                            heightFactor: week[i] == 0
                                ? 0.0
                                : week[i].clamp(6, 100) / 100,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: i == today
                                    ? WidgetLook.accent
                                    : WidgetLook.bar,
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
        const SizedBox(height: Space.half),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Text(
                  weekdayNames[i],
                  textAlign: TextAlign.center,
                  style: _text(
                    10,
                    i == today ? WidgetLook.accent : WidgetLook.day,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// 支出 or 收入 at the foot of the full widget.
class _Half extends StatelessWidget {
  const _Half({
    required this.label,
    required this.mark,
    required this.color,
    required this.tint,
    this.onTap,
  });

  final String label;
  final String mark;
  final Color color;
  final Color tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: '記$label',
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(Radii.large),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(mark, style: _text(15, color)),
              const SizedBox(width: Space.s2),
              Text(label, style: _text(14, color)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A round − or ＋ of the one-row widget.
class _Round extends StatelessWidget {
  const _Round({
    required this.mark,
    required this.label,
    required this.color,
    this.onTap,
  });

  final String mark;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Text(mark, style: _text(20, WidgetLook.onButton)),
        ),
      ),
    );
  }
}
