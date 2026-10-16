import 'package:flutter/material.dart';

import '../look/theme.dart';

/// Asks for a whole amount; null when cancelled or left empty.
Future<int?> askAmount(
  BuildContext context,
  String title, {
  int? initial,
}) async {
  final controller = TextEditingController(
    text: initial == null ? '' : '$initial',
  );
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Hue.panel,
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(prefixText: 'TWD  '),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('確定'),
        ),
      ],
    ),
  );
  final value = int.tryParse(controller.text.trim().replaceAll(',', ''));
  controller.dispose();
  return ok == true ? value : null;
}

/// Asks for a line of text; null when cancelled or left empty.
Future<String?> askText(
  BuildContext context,
  String title, {
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Hue.panel,
      title: Text(title),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('確定'),
        ),
      ],
    ),
  );
  final text = controller.text.trim();
  controller.dispose();
  return ok == true && text.isNotEmpty ? text : null;
}

/// Asks to go ahead with something that cannot be taken back easily.
Future<bool> confirm(
  BuildContext context,
  String title,
  String action, {
  bool danger = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Hue.panel,
      title: Text(title),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: danger ? Hue.danger : Hue.positive,
          ),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok == true;
}
