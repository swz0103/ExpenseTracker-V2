import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The home-screen widget 本月概況 as the phone draws it, for the web
/// preview and for 設定 › 桌面小工具: [WidgetFace] at full size
/// (summary_widget.xml) and [WidgetRow] one row high (quick_widget.xml),
/// from the snapshot the app writes (home_widget.dart). Its colours are
/// the widget's own, not the app's theme: the phone draws it on any
/// wallpaper, light or dark.
abstract final class WidgetLook {
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF26323A);
  static const muted = Color(0xFF7A858B);
  static const day = Color(0xFF9AA4A9);
  static const track = Color(0xFFEEF1EF);
  static const accent = Color(0xFF35657A);
  static const bar = Color(0xFFA9C0C8);
  static const pace = Color(0xFFC9A34A);
  static const dot = Color(0xFFD5DAD7);
  static const expense = Color(0xFF9F4535);
  static const income = Color(0xFF276B58);
  static const rule = Color(0xFFE1E4E0);
}

const _days = ['一', '二', '三', '四', '五', '六', '日'];

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
    final shown = snapshot ?? _empty;
    final budget = shown['budget'] as String? ?? '';
    final detail = shown['detail'] as String? ?? '';
    final week = (shown['week'] as List<Object?>?)?.cast<int>();
    final weekTotal = shown['weekTotal'] as String? ?? '';
    return _Card(
      radius: 26,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
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
                        shown['title'] as String? ?? '',
                        maxLines: 1,
                        style: _text(11, WidgetLook.muted),
                      ),
                    ),
                    Text(
                      shown['figure'] as String? ?? '',
                      maxLines: 1,
                      style: _text(24, WidgetLook.ink),
                    ),
                  ],
                ),
                _BudgetBar(snapshot: shown, height: 8, top: 6),
                const SizedBox(height: 4),
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
                  const SizedBox(height: 10),
                  _Week(
                    week: week,
                    total: weekTotal,
                    today: shown['today'] as int? ?? -1,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          const ColoredBox(color: WidgetLook.track, child: SizedBox(height: 1)),
          SizedBox(
            height: 40,
            child: Row(
              children: [
                Expanded(
                  child: _Half(
                    label: '支出',
                    mark: '−',
                    color: WidgetLook.expense,
                    onTap: onExpense,
                  ),
                ),
                const ColoredBox(
                  color: WidgetLook.rule,
                  child: SizedBox(width: 1, height: 22),
                ),
                Expanded(
                  child: _Half(
                    label: '收入',
                    mark: '＋',
                    color: WidgetLook.income,
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
    final shown = snapshot ?? _empty;
    return _Card(
      radius: 31,
      padding: const EdgeInsets.fromLTRB(18, 11, 9, 11),
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
                    shown['shortLabel'] as String? ??
                        shown['title'] as String? ??
                        '',
                    maxLines: 1,
                    style: _text(10.5, WidgetLook.muted),
                  ),
                  Text(
                    shown['shortFigure'] as String? ??
                        shown['figure'] as String? ??
                        '',
                    maxLines: 1,
                    style: _text(16, WidgetLook.ink),
                  ),
                  _BudgetBar(snapshot: shown, height: 6, top: 4),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _Round(
            mark: '−',
            label: '記支出',
            color: WidgetLook.expense,
            onTap: onExpense,
          ),
          const SizedBox(width: 8),
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
          BoxShadow(
            color: Color(0x1F1E2832),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
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

  final Map<String, Object?> snapshot;
  final double height;
  final double top;

  @override
  Widget build(BuildContext context) {
    final progress = snapshot['progress'] as int?;
    if (progress == null) return const SizedBox.shrink();
    final pace = snapshot['pace'] as int?;
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
        const SizedBox(height: 4),
        SizedBox(
          height: 40,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
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
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Text(
                  _days[i],
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
    this.onTap,
  });

  final String label;
  final String mark;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: '記$label',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Text(mark, style: _text(15, Colors.white)),
            ),
            const SizedBox(width: 7),
            Text(label, style: _text(14, color)),
          ],
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
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Text(mark, style: _text(20, Colors.white)),
        ),
      ),
    );
  }
}
