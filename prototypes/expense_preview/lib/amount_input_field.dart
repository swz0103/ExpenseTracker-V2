import 'package:amount_input/amount_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:foundation_values/foundation_values.dart';

import 'l10n/app_localizations.dart';

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
    final strings = AppLocalizations.of(context);
    final currency = widget.currency;
    if (!widget.enabled || currency == null) return;
    setState(() {
      _clear();
      _source = widget.controller.text;
      try {
        _result = calculateAmount(currency, _source!);
      } on AmountInputException catch (e) {
        _error = switch (e.code) {
          AmountInputError.syntax => strings.calculationSyntax,
          AmountInputError.divisionByZero => strings.calculationDivisionByZero,
          AmountInputError.complexity => strings.calculationComplexity,
        };
      } on MoneyException {
        _error = strings.calculationRange;
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
    final strings = AppLocalizations.of(context);
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
                tooltip: strings.calculateAmount,
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
                strings.calculationResult(
                  result.money.currency.code,
                  result.money.majorText,
                ),
                key: const Key('calculation-result'),
              ),
            ),
            if (result.rounded)
              Text(
                strings.calculationRounded(
                  result.money.currency.code,
                  result.money.currency.scale,
                ),
              ),
            Text(strings.calculationPercent),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: widget.enabled ? _apply : null,
                child: Text(strings.applyAmount),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
