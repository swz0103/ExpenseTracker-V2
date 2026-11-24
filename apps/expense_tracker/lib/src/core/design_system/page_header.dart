import 'package:flutter/material.dart';

import 'glyphs.dart';
import 'components/one_line.dart';
import 'theme.dart';
import 'shape.dart';
import 'spacing.dart';
import '../formatting/words.dart';

import 'package:core/time/month_arithmetic.dart';

/// A tab page's title row (總覽, 紀錄, 帳戶, 更多): the title on the left
/// in 22 px and whatever sits on the right. A page opened from another
/// has `CenterHeader` instead: back, the title in the middle.
class PageHeader extends StatelessWidget {
  const PageHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    // Clear room under the status bar before the title; taller when the
    // phone's text is larger.
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      margin: const EdgeInsets.only(top: Space.s2),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: OneLine(
                title,
                style: const TextStyle(
                  fontSize: TextSize.large,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 「‹ 2026 / 10 ›」.
class MonthSwitch extends StatelessWidget {
  const MonthSwitch({
    super.key,
    required this.month,
    required this.onChanged,
    this.latest,
  });

  final (int, int) month;
  final ValueChanged<(int, int)> onChanged;

  /// The last month that may be chosen.
  final (int, int)? latest;

  (int, int) _step(int by) {
    return shiftMonth(month.$1, month.$2, by);
  }

  @override
  Widget build(BuildContext context) {
    final (year, m) = month;
    final last = latest;
    final atEnd =
        last != null && monthIndex(year, m) >= monthIndex(last.$1, last.$2);
    return StepSwitch(
      label: '$year / $m',
      previousLabel: Words.previousMonth,
      nextLabel: Words.nextMonth,
      onPrevious: () => onChanged(_step(-1)),
      onNext: atEnd ? null : () => onChanged(_step(1)),
    );
  }
}

/// Words between a back and a forward arrow, such as a month, a week or
/// a report's period. Each arrow is a 48 dp button named for a screen
/// reader; one with nothing to do ([onPrevious] or [onNext] null) is
/// greyed out.
class StepSwitch extends StatelessWidget {
  const StepSwitch({
    super.key,
    required this.label,
    required this.previousLabel,
    required this.nextLabel,
    this.onPrevious,
    this.onNext,
    this.onLabelTap,
    this.labelHint = '選擇範圍',
    this.style = const TextStyle(
      fontSize: TextSize.title,
      fontWeight: FontWeight.w600,
    ),
    this.iconSize = 18,
    this.expand = false,
  });

  final String label;

  /// What the arrows are called, such as 上個月 and 下個月.
  final String previousLabel;
  final String nextLabel;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  /// What a tap on the words does, such as choosing a range; none leaves
  /// them as words.
  final VoidCallback? onLabelTap;

  /// What a tap on the words does, as a screen reader says it after them,
  /// such as 選擇期間; read only with [onLabelTap].
  final String labelHint;
  final TextStyle style;
  final double iconSize;

  /// Whether the words take all the room between the arrows; otherwise
  /// the switch is as wide as its parts.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final tap = onLabelTap;
    Widget words = OneLine(
      label,
      alignment: Alignment.center,
      textAlign: TextAlign.center,
      style: style,
    );
    if (tap != null) {
      // A button to a screen reader, saying what it opens.
      words = Semantics(
        button: true,
        hint: labelHint,
        child: InkWell(
          onTap: tap,
          borderRadius: BorderRadius.circular(Radii.small),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.s2,
                vertical: Space.s2,
              ),
              child: Center(widthFactor: 1, heightFactor: 1, child: words),
            ),
          ),
        ),
      );
    }
    Widget arrow(Glyph glyph, String name, VoidCallback? onPressed) =>
        IconButton(
          tooltip: name,
          onPressed: onPressed,
          icon: GlyphIcon(
            glyph,
            size: iconSize,
            color: onPressed == null ? AppColors.faint : AppColors.muted,
          ),
        );
    return Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        arrow(Glyph.back, previousLabel, onPrevious),
        if (expand) Expanded(child: words) else words,
        arrow(Glyph.next, nextLabel, onNext),
      ],
    );
  }
}

/// A page's list under its [header], which stays put while the rest
/// scrolls under it, with no line between them. [padding] is the list's,
/// its sides the header's too.
///
/// [HeadedList.lazy] takes its lines as [LineRun]s, each line built only
/// as it comes on screen: for a list as long as the book is, such as a
/// person's dealings or a loan's payments.
class HeadedList extends StatelessWidget {
  const HeadedList({
    super.key,
    required this.header,
    required List<Widget> this.children,
    this.padding = EdgeInsets.zero,
    this.physics,
  }) : runs = null;

  const HeadedList.lazy({
    super.key,
    required this.header,
    required List<LineRun> this.runs,
    this.padding = EdgeInsets.zero,
    this.physics,
  }) : children = null;

  final Widget header;
  final List<Widget>? children;
  final List<LineRun>? runs;
  final EdgeInsets padding;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    final runs = this.runs;
    final physics = this.physics ?? FitScrollPhysics(padding.bottom);
    final listPadding = padding.copyWith(top: 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: padding.left,
            right: padding.right,
            top: padding.top,
          ),
          child: header,
        ),
        Expanded(
          child: runs == null
              ? ListView(
                  physics: physics,
                  padding: listPadding,
                  children: children!,
                )
              : ListView.builder(
                  physics: physics,
                  padding: listPadding,
                  itemCount: runs.fold(0, (sum, run) => sum! + run.count),
                  itemBuilder: (context, i) {
                    for (final run in runs) {
                      if (i < run.count) return run.build(i);
                      i -= run.count;
                    }
                    return null;
                  },
                ),
        ),
      ],
    );
  }
}

/// [count] lines of a [HeadedList.lazy], the line at a place in the run
/// built by [build] when it comes on screen.
final class LineRun {
  const LineRun(this.count, this.build);

  /// One line, already made.
  LineRun.one(Widget line) : this(1, (_) => line);

  /// Each of [lines], already made.
  LineRun.each(List<Widget> lines) : this(lines.length, (i) => lines[i]);

  final int count;
  final Widget Function(int i) build;
}

/// A list that only moves when there is more than its bottom margin
/// ([slack]) to see: one whose words all fit, but for the empty room at
/// its foot, stays still under the finger.
class FitScrollPhysics extends ClampingScrollPhysics {
  const FitScrollPhysics(this.slack, {super.parent});

  final double slack;

  @override
  FitScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      FitScrollPhysics(slack, parent: buildParent(ancestor));

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) =>
      position.maxScrollExtent > slack + 1;
}
