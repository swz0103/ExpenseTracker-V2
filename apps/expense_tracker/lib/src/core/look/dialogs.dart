import 'package:flutter/material.dart';

import 'keys.dart';
import 'kit/colours.dart';
import 'theme.dart';
import 'shape.dart';
import 'spacing.dart';

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
    barrierColor: Hue.scrim,
    builder: (context) => Dialog(
      backgroundColor: Hue.paper,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: Space.s6,
        vertical: Space.s6,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.extraLarge),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.s6,
          Space.s6,
          Space.s6,
          Space.s5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: TextSize.heading,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (body != null) ...[
              const SizedBox(height: Space.s2),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: TextSize.body,
                  color: Hue.muted,
                ),
              ),
            ],
            const SizedBox(height: Space.s5),
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
                const SizedBox(width: Space.s3),
                Expanded(
                  child: _Choice(
                    action,
                    key: Keys.confirm,
                    // A deep tint with its own colour's words on the dark
                    // theme, not a bright block.
                    color: chosenFill(danger ? Hue.danger : Hue.accent),
                    ink: chosenInk(danger ? Hue.danger : Hue.accent),
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
    super.key,
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
    borderRadius: BorderRadius.circular(Radii.large),
    child: InkWell(
      borderRadius: BorderRadius.circular(Radii.large),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: TextSize.title,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
        ),
      ),
    ),
  );
}
