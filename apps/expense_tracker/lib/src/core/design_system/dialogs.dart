import 'package:flutter/material.dart';

import 'keys.dart';
import 'components/colours.dart';
import 'components/panels.dart';
import 'theme.dart';
import 'shape.dart';
import 'spacing.dart';
import '../formatting/words.dart';

// The panels in the middle of the screen that ask or tell (WP-E): one
// frame, one block of a short title with what it means under it, and one
// kind of choice along the bottom. No screen opens a dialog of its own (a
// rule in app_design_syntax_test): it asks through [confirm], [askText] or
// [tell], or puts its own words in a [DialogBlock] or a [DialogFrame].

/// The one look of a panel in the middle of the screen: on paper, with
/// round corners, close to the edges of the phone, so a title of nine
/// characters keeps one line on a 320 dp phone with the text a third
/// larger.
class DialogFrame extends StatelessWidget {
  const DialogFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: AppColors.paper,
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
      child: child,
    ),
  );
}

/// A short [title], what it means in [body] under it, then [content] (a
/// field to type in), and [choices] along the bottom: two side by side,
/// more one above another. The words scroll when they do not fit (a long
/// body, a big text size); the choices stay in view under them.
class DialogBlock extends StatelessWidget {
  const DialogBlock({
    super.key,
    required this.title,
    this.body,
    this.content,
    required this.choices,
  });

  final String title;
  final String? body;
  final Widget? content;
  final List<DialogChoice> choices;

  @override
  Widget build(BuildContext context) => DialogFrame(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: TextSize.heading,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (body case final body?) ...[
                  const SizedBox(height: Space.s2),
                  Text(body, textAlign: TextAlign.center, style: mutedBody),
                ],
                if (content case final content?) ...[
                  const SizedBox(height: Space.s4),
                  content,
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.s5),
        if (choices.length <= 2)
          Row(
            children: [
              for (final (i, choice) in choices.indexed) ...[
                if (i > 0) const SizedBox(width: Space.s3),
                Expanded(child: choice),
              ],
            ],
          )
        else
          for (final (i, choice) in choices.indexed) ...[
            if (i > 0) const SizedBox(height: Space.s2),
            choice,
          ],
      ],
    ),
  );
}

/// How a [DialogChoice] reads: grey beside the others, the one that goes
/// ahead, or one that cannot be taken back (停止, 刪除…) in red.
enum ChoiceTone { plain, main, danger }

/// One choice along the bottom of a [DialogBlock]: a wide button, grey,
/// or a deep tint with its own colour's words for [ChoiceTone.main] and
/// [ChoiceTone.danger]; greyed out while [onTap] is null.
class DialogChoice extends StatelessWidget {
  const DialogChoice(
    this.label, {
    super.key,
    required this.onTap,
    this.tone = ChoiceTone.plain,
  });

  final String label;
  final VoidCallback? onTap;
  final ChoiceTone tone;

  @override
  Widget build(BuildContext context) {
    final mark = switch (tone) {
      ChoiceTone.plain => null,
      ChoiceTone.main => AppColors.accent,
      ChoiceTone.danger => AppColors.danger,
    };
    final off = onTap == null;
    return Material(
      color: mark == null || off ? AppColors.surface : chosenFill(mark),
      borderRadius: BorderRadius.circular(Radii.large),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.large),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: TextSize.title,
                fontWeight: FontWeight.w800,
                color: off
                    ? AppColors.muted
                    : mark == null
                    ? AppColors.ink
                    : chosenInk(mark),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks to go ahead with something that cannot be taken back easily: a
/// short [title], [body] under it saying what happens when given, and
/// [cancel] (取消) beside [action], red when [danger].
Future<bool> confirm(
  BuildContext context,
  String title,
  String action, {
  bool danger = false,
  String? body,
  String cancel = Words.cancel,
}) async {
  final ok = await showPanel<bool>(
    context,
    (context) => DialogBlock(
      title: title,
      body: body,
      choices: [
        DialogChoice(
          cancel,
          key: Keys.confirmCancel,
          onTap: () => Navigator.of(context).pop(false),
        ),
        DialogChoice(
          action,
          key: Keys.confirm,
          tone: danger ? ChoiceTone.danger : ChoiceTone.main,
          onTap: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Tells [title] and, under it, [body], with one [Words.gotIt] to close.
Future<void> tell(BuildContext context, String title, String body) =>
    showPanel<void>(
      context,
      (context) => DialogBlock(
        title: title,
        body: body,
        choices: [
          DialogChoice(
            Words.gotIt,
            key: Keys.confirm,
            tone: ChoiceTone.main,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );

/// Asks which one of [items] under a short [title]: each a wide row
/// named by [label], [detail] under it when given, the words scrolling
/// when there are many, and 取消 under them; null when none is chosen.
Future<T?> chooseOne<T>(
  BuildContext context,
  List<T> items, {
  required String title,
  required String Function(T item) label,
  String Function(T item)? detail,
}) => showPanel<T>(
  context,
  (context) => DialogBlock(
    title: title,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, item) in items.indexed) ...[
          if (i > 0) const SizedBox(height: Space.s2),
          _ItemChoice(
            key: Keys.choice(i),
            label: label(item),
            detail: detail?.call(item),
            onTap: () => Navigator.of(context).pop(item),
          ),
        ],
      ],
    ),
    choices: [
      DialogChoice(
        Words.cancel,
        key: Keys.confirmCancel,
        onTap: () => Navigator.of(context).pop(),
      ),
    ],
  ),
);

/// One item [chooseOne] offers: its [label] and, under it, [detail], on
/// the grey of a [DialogChoice].
class _ItemChoice extends StatelessWidget {
  const _ItemChoice({
    super.key,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final String label;
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(Radii.large),
    child: InkWell(
      borderRadius: BorderRadius.circular(Radii.large),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s4,
          vertical: Space.s3,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: TextSize.body,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (detail case final detail?) Text(detail, style: mutedSmall),
          ],
        ),
      ),
    ),
  );
}

/// Asks for a line of text under a short [title], [body] saying what it
/// is for when given; null when cancelled or left empty. 取消 and 完成, as
/// [confirm]'s, and the keyboard's own done too.
Future<String?> askText(
  BuildContext context,
  String title, {
  String initial = '',
  String? body,
}) async {
  final text = await showPanel<String>(
    context,
    (context) => _TextDialog(title: title, body: body, initial: initial),
  );
  final trimmed = text?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// [askText]'s panel. It owns its text controller, so the controller
/// lives until the panel has finished closing, not only until it pops.
class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.body,
    required this.initial,
  });

  final String title;
  final String? body;
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

  void _done() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) => DialogBlock(
    title: widget.title,
    body: widget.body,
    content: TextField(
      key: Keys.askedText,
      controller: _controller,
      autofocus: true,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _done(),
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.large),
          borderSide: BorderSide.none,
        ),
      ),
    ),
    choices: [
      DialogChoice(
        Words.cancel,
        key: Keys.confirmCancel,
        onTap: () => Navigator.of(context).pop(),
      ),
      DialogChoice(
        Words.done,
        key: Keys.confirm,
        tone: ChoiceTone.main,
        onTap: _done,
      ),
    ],
  );
}

/// Shows [image] over the page, to pinch and zoom; a tap closes it.
Future<void> showImage(BuildContext context, ImageProvider image) =>
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(Space.s3),
        clipBehavior: Clip.antiAlias,
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: InteractiveViewer(
            maxScale: 5,
            child: Image(image: image, fit: BoxFit.contain),
          ),
        ),
      ),
    );
