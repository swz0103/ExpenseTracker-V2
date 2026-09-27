import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:foundation_values/foundation_values.dart';

import 'l10n/app_localizations.dart';
import 'business_calendar.dart';

/// Raw manual input remains a draft. Only a confirmed calendar selection becomes
/// ISO business-date text; neither path commits a ledger entry.
class BusinessDateInputField extends StatefulWidget {
  const BusinessDateInputField({
    super.key,
    required this.controller,
    required this.label,
    required this.help,
    required this.enabled,
    required this.canApply,
    required this.onChanged,
  });
  final TextEditingController controller;
  final String label;
  final String help;
  final bool enabled;
  // The owner checks its session immediately, before a rebuild can disable us.
  final bool Function() canApply;
  final VoidCallback onChanged;

  @override
  State<BusinessDateInputField> createState() => _BusinessDateInputFieldState();
}

class _BusinessDateInputFieldState extends State<BusinessDateInputField> {
  int _revision = 0;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  void _changed() => _revision++;

  @override
  void didUpdateWidget(BusinessDateInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _revision++;
    }
    if (oldWidget.enabled != widget.enabled) _revision++;
  }

  Future<void> _pick() async {
    if (_picking || !widget.enabled || !widget.canApply()) return;
    final controller = widget.controller;
    final revision = _revision;
    final canApply = widget.canApply;
    BusinessDate? initial;
    try {
      initial = BusinessDate.parse(controller.text);
    } on FormatException {
      // Invalid/partial text is preserved unless the user confirms a selection.
    }
    final now = DateTime.now();
    final strings = AppLocalizations.of(context);
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _picking = true);
    try {
      final selected = await showDatePicker(
        context: context,
        calendarDelegate: const BusinessCalendar(),
        initialDate: initial == null
            ? DateTime.utc(now.year, now.month, now.day)
            : DateTime.utc(initial.year, initial.month, initial.day),
        firstDate: DateTime.utc(1),
        lastDate: DateTime.utc(9999, 12, 31),
        // Manual ISO entry is available in the original field. A second locale-
        // dependent text parser in the dialog would create conflicting formats.
        initialEntryMode: DatePickerEntryMode.calendarOnly,
        helpText: widget.help,
        builder: (context, child) {
          final theme = Theme.of(context);
          // The SDK header has fixed height. Keep its full date readable when
          // Traditional Chinese text wraps on narrow, enlarged-font screens.
          return Theme(
            data: theme.copyWith(
              datePickerTheme: DatePickerTheme.of(context)
                  .copyWith(headerHeadlineStyle: theme.textTheme.titleLarge),
            ),
            child: child!,
          );
        },
        cancelText: strings.cancel,
        confirmText: strings.confirmDate,
      );
      if (!mounted ||
          selected == null ||
          !canApply() ||
          !widget.canApply() ||
          !widget.enabled ||
          controller != widget.controller ||
          revision != _revision) {
        return;
      }
      // Civil calendar components, never a UTC conversion or a midnight instant.
      final text = BusinessDate(
        selected.year,
        selected.month,
        selected.day,
      ).toString();
      if (text == controller.text) return;
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      widget.onChanged();
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: widget.controller,
      enabled: widget.enabled,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.datetime,
      maxLength: 32,
      // Preserve the whole previous value when a paste exceeds the draft bound.
      inputFormatters: [
        TextInputFormatter.withFunction(
          (before, after) => after.text.length <= 32 ? after : before,
        ),
      ],
      onChanged: (_) => widget.onChanged(),
      decoration: InputDecoration(
        labelText: widget.label,
        suffixIcon: IconButton(
          tooltip: AppLocalizations.of(context).selectDate,
          onPressed: widget.enabled && !_picking ? _pick : null,
          icon: const Icon(Icons.calendar_month_outlined),
        ),
      ),
    ),
  );
}
