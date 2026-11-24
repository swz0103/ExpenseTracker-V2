import 'package:flutter/material.dart';

import 'keys.dart';
import 'components/colours.dart';
import 'theme.dart';
import 'shape.dart';
import 'spacing.dart';
import '../formatting/words.dart';

/// Asks for a line of text; null when cancelled or left empty.
Future<String?> askText(
  BuildContext context,
  String title, {
  String initial = '',
}) async {
  final text = await showDialog<String>(
    context: context,
    builder: (context) => _TextDialog(title: title, initial: initial),
  );
  final trimmed = text?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// [askText]'s panel. It owns its text controller, so the controller
/// lives until the panel has finished closing, not only until it pops.
class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: AppColors.panel,
    title: Text(widget.title),
    content: TextField(controller: _controller, autofocus: true),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text(Words.cancel),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_controller.text),
        child: const Text('確定'),
      ),
    ],
  );
}

/// Asks to go ahead with something that cannot be taken back easily: a
/// panel in the middle of the screen with [title], [body] under it when
/// given, and [cancel] (取消) beside [action], red when [danger].
Future<bool> confirm(
  BuildContext context,
  String title,
  String action, {
  bool danger = false,
  String? body,
  String cancel = Words.cancel,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (context) => Dialog(
      backgroundColor: AppColors.paper,
      // Close to the edges, so a title of nine characters keeps one line
      // on a 320 dp phone with the text a third larger.
      insetPadding: const EdgeInsets.symmetric(
        horizontal: Space.s4,
        vertical: Space.s6,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.extraLarge),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.s5,
          Space.s6,
          Space.s5,
          Space.s5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The words scroll when they do not fit (a long body, a big
            // text size); the two choices stay in view under them.
            Flexible(
              child: SingleChildScrollView(
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
                      Text(body, textAlign: TextAlign.center, style: mutedBody),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.s5),
            Row(
              children: [
                Expanded(
                  child: _Choice(
                    cancel,
                    key: Keys.confirmCancel,
                    color: AppColors.surface,
                    ink: AppColors.ink,
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
                    color: chosenFill(
                      danger ? AppColors.danger : AppColors.accent,
                    ),
                    ink: chosenInk(
                      danger ? AppColors.danger : AppColors.accent,
                    ),
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
