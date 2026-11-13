import 'package:flutter/material.dart';

import 'theme.dart';

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

/// Asks to go ahead with something that cannot be taken back easily: a
/// panel in the middle of the screen with [title], [body] under it when
/// given, and 取消 beside [action], red when [danger].
Future<bool> confirm(
  BuildContext context,
  String title,
  String action, {
  bool danger = false,
  String? body,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0x66222B30),
    builder: (context) => Dialog(
      backgroundColor: Hue.paper,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            if (body != null) ...[
              const SizedBox(height: 10),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Hue.muted),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _Choice(
                    '取消',
                    color: Hue.surface,
                    ink: Hue.ink,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Choice(
                    action,
                    color: danger ? Hue.danger : Hue.accent,
                    ink: Hue.onAccent,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return ok == true;
}

class _Choice extends StatelessWidget {
  const _Choice(
    this.label, {
    required this.color,
    required this.ink,
    required this.onTap,
  });

  final String label;
  final Color color;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: color,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
        ),
      ),
    ),
  );
}
