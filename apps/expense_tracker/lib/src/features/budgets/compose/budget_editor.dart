import 'package:flutter/material.dart';

import '../../../core/ledger/ledger.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/shape.dart';
import '../../../core/look/spacing.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/text/figures.dart';
import '../../../core/ui/calculator.dart';
import '../../../core/ui/icons.dart';
import '../../../core/ui/shown_amounts.dart';
import '../model/budget_month.dart';

/// Opens the form of [budget] as a bottom sheet; saving or removing it
/// writes to [ledger] directly.
Future<void> editBudget(BuildContext context, Ledger ledger, Budget budget) =>
    showSheet<void>(
      context,
      (_) => _BudgetEditor(ledger: ledger, budget: budget),
    );

/// A budget's form, the card itself: its icon and name, the monthly
/// allowance in big figures (the calculator beside), this month's use on
/// a bar with the warning line; then the share to warn at, whether what
/// is left carries over, and 儲存. A category's or tag's has a bin.
class _BudgetEditor extends StatefulWidget {
  const _BudgetEditor({required this.ledger, required this.budget});

  final Ledger ledger;
  final Budget budget;

  @override
  State<_BudgetEditor> createState() => _BudgetEditorState();
}

class _BudgetEditorState extends State<_BudgetEditor> {
  late var _limit = widget.budget.limit;
  late var _warning = widget.budget.warning;
  late var _carry = widget.budget.carry;

  static const _shares = [70, 80, 90, 100];

  Future<void> _calculate() async {
    final value = await showCalculator(
      context,
      title: '每月額度',
      initial: _limit,
      color: Hue.accent,
    );
    if (value != null) setState(() => _limit = value);
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final name = widget.budget.category;
    final category = BudgetScope.of(name) == BudgetScope.category
        ? ledger.category(name)
        : null;
    final shade = category?.color;
    final color = shade == null ? Hue.accent : Color(shade);
    final today = ledger.today;
    final used = BudgetMonth.of(ledger, (
      today.year,
      today.month,
    )).spentOn(widget.budget);
    final ink = deepOf(color);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(Space.s4),
            decoration: BoxDecoration(
              color: tintOf(color, 0.24),
              borderRadius: BorderRadius.circular(Radii.largeIncreased),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _head(category, color),
                const SizedBox(height: Space.s4),
                _allowance(ink),
                const SizedBox(height: Space.s2),
                _UsageBar(
                  used: used,
                  limit: _limit,
                  warning: _warning,
                  color: color,
                ),
                const SizedBox(height: Space.s2),
                _usage(used, ink),
              ],
            ),
          ),
          const SizedBox(height: Space.s4),
          const Text(
            '用到幾成時提醒',
            style: TextStyle(
              fontSize: TextSize.body,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Space.s2),
          _warningChoices(),
          const SizedBox(height: Space.s3),
          _carrySwitch(),
          const SizedBox(height: Space.s4),
          PanelButton(
            '儲存',
            color: Hue.accent,
            onTap: () {
              ledger.budgetCommands.setBudget(
                name,
                _limit,
                warning: _warning,
                carry: _carry,
              );
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  /// The icon, what the budget is on, and a bin for all but the total.
  Widget _head(Category? category, Color color) {
    final name = widget.budget.category;
    final scope = BudgetScope.of(name);
    final total = scope == BudgetScope.all;
    final ink = deepOf(color);
    final glyph = switch ((scope, category)) {
      (_, final c?) => iconFor(c.icon),
      (BudgetScope.all, null) => Glyph.cash,
      (_, null) => Glyph.tag,
    };
    return Row(
      children: [
        SquareIcon(glyph, color, size: 52),
        const SizedBox(width: Space.s4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                total ? '總預算' : name,
                style: TextStyle(
                  fontSize: TextSize.large,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              Text(switch (scope) {
                BudgetScope.all => '這個月所有支出',
                BudgetScope.tag => '標籤額度',
                BudgetScope.category => '分類額度',
              }, style: TextStyle(fontSize: TextSize.small, color: ink)),
            ],
          ),
        ),
        if (!total)
          Material(
            color: Hue.white,
            borderRadius: BorderRadius.circular(Radii.large),
            child: IconButton(
              tooltip: '移除額度',
              onPressed: () {
                widget.ledger.budgetCommands.removeBudget(name);
                Navigator.of(context).pop();
              },
              icon: const GlyphIcon(Glyph.trash, size: 18, color: Hue.danger),
            ),
          ),
      ],
    );
  }

  /// 每月額度 in big figures; a tap opens the calculator.
  Widget _allowance(Color ink) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '每月額度',
          style: TextStyle(
            fontSize: TextSize.small,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
        AmountTap(
          label: '每月額度 $_limit',
          onTap: _calculate,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${currencyLabel(homeCode)} ',
                  style: const TextStyle(
                    fontSize: TextSize.heading,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: groupDigits(_limit),
                  style: const TextStyle(
                    fontSize: TextSize.hero,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 這個月已用 and the share warned at, at the two ends, or the second
  /// under the first when both do not fit, as with large text on a small
  /// phone.
  Widget _usage(int used, Color ink) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      runSpacing: Space.s1,
      children: [
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: '這個月已用 '),
              TextSpan(
                text: widget.ledger.orDots(groupDigits(used)),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          style: TextStyle(fontSize: TextSize.small, color: ink),
        ),
        Text(
          '$_warning% 時提醒',
          style: TextStyle(fontSize: TextSize.small, color: ink),
        ),
      ],
    );
  }

  /// The share of the limit at which to be told: 70% to 100%.
  Widget _warningChoices() => Row(
    children: [
      for (final (i, p) in _shares.indexed) ...[
        if (i > 0) const SizedBox(width: Space.s2),
        Expanded(
          child: Material(
            color: p == _warning ? Hue.accent : Hue.surface,
            borderRadius: BorderRadius.circular(Radii.large),
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.large),
              onTap: () => setState(() => _warning = p),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                // Shrinks a little with the phone's largest text, so 100%
                // stays on one line.
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$p%',
                      style: TextStyle(
                        fontSize: TextSize.title,
                        fontWeight: FontWeight.w800,
                        color: p == _warning ? Hue.onAccent : Hue.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ],
  );

  /// Whether what is left carries into the next month.
  Widget _carrySwitch() => ColorCard(
    controlsInside: true,
    color: Hue.faint,
    amount: 0.15,
    radius: Radii.large,
    onTap: () => setState(() => _carry = !_carry),
    padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s2, Space.s2),
    child: Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '沒用完的留到下個月',
                style: TextStyle(
                  fontSize: TextSize.body,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text('上個月剩的，加到這個月的額度', style: mutedSmall),
            ],
          ),
        ),
        TickSwitch(
          value: _carry,
          color: Hue.accent,
          label: '沒用完的留到下個月',
          onChanged: (on) => setState(() => _carry = on),
        ),
      ],
    ),
  );
}

/// This month's use of a budget on a bar, filled up to [limit], with a
/// line where [warning] (a percentage) falls.
class _UsageBar extends StatelessWidget {
  const _UsageBar({
    required this.used,
    required this.limit,
    required this.warning,
    required this.color,
  });

  final int used;
  final int limit;
  final int warning;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final share = limit == 0 ? 0.0 : (used / limit).clamp(0.0, 1.0);
        final line = box.maxWidth * warning / 100;
        return SizedBox(
          height: 18,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              _track(Hue.white),
              FractionallySizedBox(widthFactor: share, child: _track(color)),
              Positioned(
                left: (line - 1).clamp(0, box.maxWidth - 2),
                top: 0,
                bottom: 0,
                child: Container(width: 2, color: Hue.ink),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _track(Color fill) => Container(
    height: 10,
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(Radii.extraSmall),
    ),
  );
}
