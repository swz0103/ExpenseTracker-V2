import 'package:flutter/material.dart';

import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/theme.dart';

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
/// the whole amount, or null when dismissed.
Future<int?> showCalculator(
  BuildContext context, {
  required String title,
  required int initial,
  required Color color,
  String unit = 'TWD',
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Hue.panel,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: _Calculator(
        title: title,
        initial: initial,
        color: color,
        unit: unit,
      ),
    ),
  );
}

class _Calculator extends StatefulWidget {
  const _Calculator({
    required this.title,
    required this.initial,
    required this.color,
    required this.unit,
  });

  final String title;
  final int initial;
  final Color color;
  final String unit;

  @override
  State<_Calculator> createState() => _CalculatorState();
}

class _CalculatorState extends State<_Calculator> {
  late var _expression = widget.initial == 0 ? '' : '${widget.initial}';

  static const _rows = [
    ['C', '⌫', '÷', '×'],
    ['7', '8', '9', '−'],
    ['4', '5', '6', '+'],
    ['1', '2', '3', '='],
    ['0', '00', '.', '完成'],
  ];

  void _press(String key) {
    setState(() {
      switch (key) {
        case 'C':
          _expression = '';
        case '⌫':
          if (_expression.isNotEmpty) {
            _expression = _expression.substring(0, _expression.length - 1);
          }
        case '=':
          final value = evaluate(_expression);
          if (value != null) _expression = _plain(value);
        case '完成':
          final value = evaluate(_expression) ?? 0;
          final amount = value.round().clamp(0, 999999999);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop(amount);
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

  String _plain(double value) => value == value.roundToDouble()
      ? '${value.round()}'
      : value.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final value = evaluate(_expression);
    final shown = value == null ? '…' : groupDigits(value.round());
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '返回',
                onPressed: () => Navigator.of(context).pop(),
                icon: const GlyphIcon(Glyph.back),
              ),
              Expanded(
                child: Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                widget.unit,
                style: const TextStyle(fontSize: 12, color: Hue.muted),
              ),
              const SizedBox(width: 10),
              Text(
                shown,
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w500,
                  color: widget.color,
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              _expression.isEmpty ? '0' : _expression,
              style: const TextStyle(fontSize: 14, color: Hue.muted),
            ),
          ),
          const SizedBox(height: 18),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.65,
            children: [
              for (final row in _rows)
                for (final key in row) _key(key),
            ],
          ),
        ],
      ),
    );
  }

  Widget _key(String key) {
    final operator = '÷×−+='.contains(key);
    final done = key == '完成';
    final background = done
        ? const Color(0xFF5B7B5F)
        : operator
        ? Hue.mist
        : Hue.surface;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _press(key),
        child: Center(
          child: key == '⌫'
              ? const GlyphIcon(Glyph.backspace, size: 22)
              : Text(
                  key,
                  style: TextStyle(
                    fontSize: done ? 14 : 20,
                    color: done
                        ? Hue.white
                        : key == 'C'
                        ? Hue.danger
                        : Hue.ink,
                  ),
                ),
        ),
      ),
    );
  }
}
