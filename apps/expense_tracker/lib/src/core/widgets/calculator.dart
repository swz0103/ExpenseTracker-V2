import 'package:core/foundation_values.dart' show Currency;
import 'package:flutter/material.dart';

import '../formatting/figures.dart';
import '../design_system/glyphs.dart';
import '../design_system/haptics.dart';
import '../design_system/theme.dart';
import '../design_system/design_system.dart';
import 'amount_keys.dart';
import '../design_system/shape.dart';
import '../design_system/spacing.dart';
import '../formatting/words.dart';

export 'amount_keys.dart';

/// The amount calculator: digits and the four operations; 完成 returns
/// the amount in the smallest unit of [unit] (whole NT$, US cents), or
/// null when dismissed.
Future<int?> showCalculator(
  BuildContext context, {
  required String title,
  required int initial,
  required Color color,
  String unit = 'TWD',
}) async {
  final cents = takesCents(unit);
  final value = await showSheet<num>(
    context,
    (_) => _Calculator(
      title: title,
      initial: initial == 0
          ? ''
          : cents
          ? _plain(initial / 100)
          : '$initial',
      color: color,
      unit: unit,
      decimal: cents,
    ),
  );
  if (value == null) return null;
  return cents ? (value * 100).round() : value.round();
}

/// The calculator for a price with two decimals, such as 194.35.
Future<double?> showPriceCalculator(
  BuildContext context, {
  required String title,
  required double initial,
  required Color color,
}) async {
  final value = await showSheet<num>(
    context,
    (_) => _Calculator(
      title: title,
      initial: initial == 0 ? '' : _plain(initial),
      color: color,
      unit: '元／股',
      decimal: true,
    ),
  );
  return value?.toDouble();
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

String _plain(double value) => value == value.roundToDouble()
    ? '${value.round()}'
    : value.toStringAsFixed(2);

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
      final result = _keys.result;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(result);
      });
      return;
    }
    setState(() => _keys.press(key));
  }

  @override
  Widget build(BuildContext context) {
    final value = _keys.value;
    final shown = value == null
        ? '…'
        : widget.decimal
        ? _plain(value)
        : groupDigits(value.round());
    final working = _keys.working;
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
          Container(
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
                Text(
                  working ? _keys.expression : widget.unit,
                  style: mutedBody,
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    shown,
                    style: TextStyle(
                      fontSize: TextSize.hero,
                      fontWeight: FontWeight.w700,
                      color: widget.color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.s4),
          SizedBox(
            height: 5 * 54 + 4 * 8,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
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
                  ),
                ),
                const SizedBox(width: Space.s2),
                Expanded(
                  child: Column(
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
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _key(String key) {
    final operator = '÷×−+'.contains(key);
    final done = key == Words.done;
    final background = done
        ? chosenFill(AppColors.accent)
        : operator || key == 'C' || key == '⌫'
        ? AppColors.hero
        : AppColors.tile;
    final ink = done
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
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.large),
          onTap: () => _press(key),
          child: Center(
            child: key == '⌫'
                ? Semantics(
                    label: Words.delete,
                    child: GlyphIcon(
                      Glyph.backspace,
                      size: 24,
                      color: AppColors.accent,
                    ),
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
    );
  }
}
