import 'package:amount_input/amount_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:foundation_values/foundation_values.dart';

/// Calculation is only a proposal. Typing and explicit application use the same
/// parent change callback, so the existing encrypted draft owns persistence.
class AmountInputField extends StatefulWidget {
  const AmountInputField({
    super.key,
    required this.controller,
    required this.label,
    required this.currency,
    required this.enabled,
    required this.onChanged,
  });
  final TextEditingController controller;
  final String label;
  final Currency? currency;
  final bool enabled;
  final VoidCallback onChanged;
  @override
  State<AmountInputField> createState() => _AmountInputFieldState();
}

class _AmountInputFieldState extends State<AmountInputField> {
  AmountCalculation? _result;
  String? _source, _error;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_invalidate);
  }

  @override
  void didUpdateWidget(AmountInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_invalidate);
      widget.controller.addListener(_invalidate);
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.currency != widget.currency ||
        oldWidget.enabled != widget.enabled) {
      _clear();
    }
  }

  void _clear() {
    _result = null;
    _source = null;
    _error = null;
  }

  void _invalidate() {
    if (_source != widget.controller.text &&
        (_result != null || _error != null)) {
      setState(_clear);
    }
  }

  void _calculate() {
    final currency = widget.currency;
    if (!widget.enabled || currency == null) return;
    setState(() {
      _clear();
      _source = widget.controller.text;
      try {
        _result = calculateAmount(currency, _source!);
      } on AmountInputException catch (e) {
        _error = switch (e.code) {
          AmountInputError.syntax => '請檢查算式、括號與小數點。',
          AmountInputError.divisionByZero => '不能除以零，請修改算式。',
          AmountInputError.complexity => '算式過長或過於複雜，請分段計算。',
        };
      } on MoneyException {
        _error = '計算結果超出可保存的金額範圍。';
      }
    });
  }

  void _apply() {
    final result = _result;
    if (!widget.enabled ||
        result == null ||
        _source != widget.controller.text ||
        result.money.currency != widget.currency) {
      return;
    }
    final text = result.money.majorText;
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(_clear);
    widget.onChanged();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_invalidate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: widget.controller,
            enabled: widget.enabled,
            autocorrect: false,
            enableSuggestions: false,
            maxLength: 128,
            // Reject the entire edit: truncating a paste can change its value.
            inputFormatters: [
              TextInputFormatter.withFunction(
                (before, after) => after.text.length <= 128 ? after : before,
              ),
            ],
            onChanged: (_) => widget.onChanged(),
            decoration: InputDecoration(
              labelText: widget.label,
              suffixIcon: IconButton(
                tooltip: '計算金額',
                onPressed: widget.enabled && widget.currency != null
                    ? _calculate
                    : null,
                icon: const Icon(Icons.calculate_outlined),
              ),
            ),
          ),
          if (_error != null)
            Semantics(
              liveRegion: true,
              child: Text(_error!, key: const Key('calculation-error')),
            ),
          if (result != null) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                '計算結果：${result.money.currency.code} ${result.money.majorText}',
                key: const Key('calculation-result'),
              ),
            ),
            if (result.rounded)
              Text(
                '結果已依 ${result.money.currency.code} 小數 ${result.money.currency.scale} 位四捨五入。',
              ),
            const Text('10% = 0.1；折扣例：100 × (1 − 10%)。'),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: widget.enabled ? _apply : null,
                child: const Text('套用結果'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
