import 'package:core/foundation_values.dart' show Currency;
import 'package:flutter/material.dart';

import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/haptics.dart';
import '../look/theme.dart';
import '../look/widgets.dart';

/// Works out `12+3×4−5÷2` with × and ÷ before + and −. Returns null for
/// an expression that cannot be read, such as a trailing operator.
double? evaluate(String expression) {
  final tokens = <String>[];
  final number = StringBuffer();
  for (final char in expression.split('')) {
    if ('+−×÷'.contains(char)) {
      if (number.isEmpty) return null;
      tokens
        ..add(number.toString())
        ..add(char);
      number.clear();
    } else {
      number.write(char);
    }
  }
  if (number.isEmpty) return tokens.isEmpty ? 0 : null;
  tokens.add(number.toString());
  final terms = <double>[];
  final signs = <String>[];
  final first = double.tryParse(tokens.first);
  if (first == null) return null;
  var current = first;
  for (var i = 1; i < tokens.length; i += 2) {
    final op = tokens[i];
    final value = double.tryParse(tokens[i + 1]);
    if (value == null) return null;
    if (op == '×') {
      current = current * value;
    } else if (op == '÷') {
      if (value == 0) return null;
      current = current / value;
    } else {
      terms.add(current);
      signs.add(op);
      current = value;
    }
  }
  terms.add(current);
  var result = terms.first;
  for (var i = 0; i < signs.length; i++) {
    result = signs[i] == '+' ? result + terms[i + 1] : result - terms[i + 1];
  }
  return result;
}

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
  final cents = Currency.supported.contains(unit) && Currency.scaleOf(unit) > 0;
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

final _trailing = RegExp('[+−×÷]+\$');

class _CalculatorState extends State<_Calculator> {
  late var _expression = widget.initial;

  void _press(String key) {
    Haptics.selection();
    setState(() {
      switch (key) {
        case 'C':
          _expression = '';
        case '⌫':
          if (_expression.isNotEmpty) {
            _expression = _expression.substring(0, _expression.length - 1);
          }
        case '完成':
          // A sum left open, such as 120+, counts what was typed.
          final value = evaluate(_expression.replaceAll(_trailing, '')) ?? 0;
          final num result = widget.decimal
              ? double.parse(value.clamp(0, 99999999).toStringAsFixed(2))
              : value.round().clamp(0, 999999999);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop(result);
          });
        case '+' || '−' || '×' || '÷':
          if (_expression.isEmpty) return;
          final last = _expression[_expression.length - 1];
          final trimmed = '+−×÷'.contains(last)
              ? _expression.substring(0, _expression.length - 1)
              : _expression;
          _expression = '$trimmed$key';
        default:
          if (_expression.length < 18) _expression += key;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final value = evaluate(_expression);
    final shown = value == null
        ? '…'
        : widget.decimal
        ? _plain(value)
        : groupDigits(value.round());
    final working = _expression.contains(RegExp('[+−×÷]'));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
            decoration: BoxDecoration(
              color: Hue.hero,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  working ? _expression : widget.unit,
                  style: const TextStyle(fontSize: 14, color: Hue.muted),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    shown,
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w700,
                      color: widget.color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
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
                        if (i > 0) const SizedBox(height: 8),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final (j, key) in row.indexed) ...[
                                if (j > 0) const SizedBox(width: 8),
                                Expanded(child: _key(key)),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _key('×')),
                      const SizedBox(height: 8),
                      Expanded(child: _key('−')),
                      const SizedBox(height: 8),
                      Expanded(child: _key('+')),
                      const SizedBox(height: 8),
                      Expanded(flex: 2, child: _key('完成')),
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
    final done = key == '完成';
    final background = done
        ? Hue.accent
        : operator || key == 'C' || key == '⌫'
        ? Hue.hero
        : Hue.tile;
    final ink = done
        ? Hue.onAccent
        : operator || key == 'C' || key == '⌫'
        ? Hue.accent
        : Hue.ink;
    return Pressable(
      depth: 0.93,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _press(key),
          child: Center(
            child: key == '⌫'
                ? const GlyphIcon(Glyph.backspace, size: 24, color: Hue.accent)
                : Text(
                    key,
                    style: TextStyle(
                      fontSize: done ? 16 : 24,
                      fontWeight: done ? FontWeight.w700 : FontWeight.w500,
                      color: ink,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
