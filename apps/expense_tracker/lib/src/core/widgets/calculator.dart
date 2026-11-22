import 'package:core/foundation_values.dart' show Currency;
import 'package:core/money/amount_format.dart' show roundHalfAwayFromZero;
import 'package:core/money/amount_parser.dart';
import 'package:flutter/material.dart';

import '../../../design_system/display/amount.dart';
import '../design_system/glyphs.dart';
import '../design_system/haptics.dart';
import '../design_system/theme.dart';
import '../design_system/design_system.dart';
import 'amount_keys.dart';
import '../design_system/shape.dart';
import '../design_system/spacing.dart';
import '../formatting/words.dart';
import '../messages/amount_messages.dart';

export 'amount_keys.dart';

/// The amount calculator: digits and the four operations; 完成 returns
/// the amount in the smallest unit of [unit] (whole NT$, US cents), or
/// null when dismissed. A sum that is not an amount (÷0, below zero,
/// past 999,999,999) says why, and 完成 waits until it is one.
Future<int?> showCalculator(
  BuildContext context, {
  required String title,
  required int initial,
  required Color color,
  String unit = 'TWD',
}) async {
  final cents = takesCents(unit);
  return showSheet<int>(
    context,
    (_) => _Calculator(
      title: title,
      // The keys type no minus: a balance below zero starts from nothing.
      initial: initial <= 0 ? '' : keyedAmount(initial, cents ? 2 : 0),
      color: color,
      unit: unit,
      decimal: cents,
    ),
  );
}

/// The calculator for a price with two decimals, such as 194.35.
Future<double?> showPriceCalculator(
  BuildContext context, {
  required String title,
  required double initial,
  required Color color,
}) async {
  final cents = await showSheet<int>(
    context,
    (_) => _Calculator(
      title: title,
      initial: initial == 0
          ? ''
          : keyedAmount(roundHalfAwayFromZero(initial, 2), 2),
      color: color,
      unit: '元／股',
      decimal: true,
    ),
  );
  return cents == null ? null : cents / 100;
}

/// An amount to change with the calculator: all of it opens it, the
/// figure in [child] and the calculator mark beside it, which only says
/// so. At least 48 dp high, read out as [label].
class AmountTap extends StatelessWidget {
  const AmountTap({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.large),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(fit: BoxFit.scaleDown, child: child),
                  ),
                ),
                if (onTap != null)
                  const Padding(
                    padding: EdgeInsets.all(Space.s3),
                    child: GlyphIcon(
                      Glyph.calculator,
                      size: 20,
                      color: AppColors.muted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Whether amounts in [unit] are typed with two decimals, such as US$.
bool takesCents(String unit) =>
    Currency.supported.contains(unit) && Currency.scaleOf(unit) > 0;

/// What a key is called aloud: 減 for −, 兩個零 for 00.
String _spokenKey(String key) => switch (key) {
  '÷' => '除以',
  '×' => '乘以',
  '−' => '減',
  '+' => '加',
  'C' => '清除',
  '⌫' => Words.delete,
  '00' => '兩個零',
  '000' => '三個零',
  '.' => '小數點',
  _ => key,
};

class _Calculator extends StatefulWidget {
  const _Calculator({
    required this.title,
    required this.initial,
    required this.color,
    required this.unit,
    this.decimal = false,
  });

  final String title;
  final String initial;
  final Color color;
  final String unit;
  final bool decimal;

  @override
  State<_Calculator> createState() => _CalculatorState();
}

class _CalculatorState extends State<_Calculator> {
  late final _keys = AmountKeys(widget.initial, decimal: widget.decimal);

  void _press(String key) {
    Haptics.selection();
    if (key == Words.done) {
      // Only an amount is kept, the one shown; otherwise the reason
      // stays on screen.
      final amount = _keys.amount;
      if (amount is! AmountOk) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(amount.minor);
      });
      return;
    }
    setState(() => _keys.press(key));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: TextSize.title,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Space.s3),
          _display(),
          const SizedBox(height: Space.s4),
          SizedBox(
            height: 5 * 54 + 4 * 8,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: _digits()),
                const SizedBox(width: Space.s2),
                Expanded(child: _operators()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The amount so far, large in the calculator's colour, with the sum
  /// being worked above it (or the unit when there is none), and why it
  /// cannot be kept when it is not an amount.
  Widget _display() {
    final amount = _keys.amount;
    final scale = _keys.scale;
    final shown = switch (amount) {
      AmountOk(:final minor) => keyedResult(minor, scale),
      AmountRefused(:final cameTo?) when cameTo.isValidInt =>
        cameTo.isNegative
            ? '−${keyedResult(-cameTo.toInt(), scale)}'
            : keyedResult(cameTo.toInt(), scale),
      AmountRefused() => '…',
    };
    final problem = switch (amount) {
      AmountRefused(:final problem) => amountProblemMessage(problem),
      AmountOk() => null,
    };
    final working = _keys.working;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s3,
        Space.s4,
        Space.s4,
      ),
      decoration: BoxDecoration(
        color: AppColors.hero,
        borderRadius: BorderRadius.circular(Radii.largeIncreased),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(working ? _keys.expression : widget.unit, style: mutedBody),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              shown,
              style: TextStyle(
                fontSize: TextSize.hero,
                fontWeight: FontWeight.w700,
                color: problem == null ? widget.color : AppColors.muted,
              ),
            ),
          ),
          if (problem != null)
            Text(
              problem,
              key: Keys.calcProblem,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: TextSize.small,
                fontWeight: FontWeight.w600,
                color: AppColors.danger,
              ),
            ),
        ],
      ),
    );
  }

  /// The digits, clear and delete, three to a row.
  Widget _digits() => Column(
    children: [
      for (final (i, row) in [
        ['C', '⌫', '÷'],
        ['7', '8', '9'],
        ['4', '5', '6'],
        ['1', '2', '3'],
        ['00', '0', if (widget.decimal) '.' else '000'],
      ].indexed) ...[
        if (i > 0) const SizedBox(height: Space.s2),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (j, key) in row.indexed) ...[
                if (j > 0) const SizedBox(width: Space.s2),
                Expanded(child: _key(key)),
              ],
            ],
          ),
        ),
      ],
    ],
  );

  /// The operations down the side, 完成 twice as tall at the bottom.
  Widget _operators() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(child: _key('×')),
      const SizedBox(height: Space.s2),
      Expanded(child: _key('−')),
      const SizedBox(height: Space.s2),
      Expanded(child: _key('+')),
      const SizedBox(height: Space.s2),
      Expanded(flex: 2, child: _key(Words.done)),
    ],
  );

  Widget _key(String key) {
    final operator = '÷×−+'.contains(key);
    final done = key == Words.done;
    // 完成 waits while the sum is not an amount.
    final held = done && _keys.amount is! AmountOk;
    final background = held
        ? AppColors.tile
        : done
        ? chosenFill(AppColors.accent)
        : operator || key == 'C' || key == '⌫'
        ? AppColors.hero
        : AppColors.tile;
    final ink = held
        ? AppColors.muted
        : done
        ? chosenInk(AppColors.accent)
        : operator || key == 'C' || key == '⌫'
        ? AppColors.accent
        : AppColors.ink;
    return Pressable(
      key: Keys.calc(key),
      depth: 0.93,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(Radii.large),
        child: Semantics(
          button: true,
          enabled: !held,
          label: _spokenKey(key),
          // The key itself, as the words inside are left out.
          onTap: held ? null : () => _press(key),
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.large),
            onTap: () => _press(key),
            child: Center(
              child: key == '⌫'
                  ? GlyphIcon(
                      Glyph.backspace,
                      size: 24,
                      color: AppColors.accent,
                    )
                  // 000 on a narrow phone with its largest text shrinks a
                  // little rather than wraps.
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        key,
                        style: TextStyle(
                          fontSize: done ? TextSize.title : TextSize.large,
                          fontWeight: done ? FontWeight.w700 : FontWeight.w500,
                          color: ink,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
