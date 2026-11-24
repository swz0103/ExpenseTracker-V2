import 'package:flutter/material.dart';

import '../../../core/design_system/shape.dart';
import '../../../core/formatting/words.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import 'compose_widgets.dart';

/// A choice opened inside the sheet in place of the form: [title] with
/// the arrow back on its left, and [body] under it, scrolling. Going back
/// with the system's back gesture closes it too ([onBack]), not the
/// sheet.
class SubpageFrame extends StatelessWidget {
  const SubpageFrame({
    super.key,
    required this.title,
    required this.onBack,
    required this.body,
  });

  final String title;
  final VoidCallback onBack;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s2),
            child: SubpageHeader(title: title, onBack: onBack),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                Space.s4,
                Space.s3,
                Space.s4,
                Space.s4,
              ),
              child: body,
            ),
          ),
        ],
      ),
    );
  }
}

/// The foot of the entry form: [discard] (刪除 or 暫存) in words, 退款
/// when [onRefund] is given, 取消 while it is being written ([cancel],
/// D83), and the main button, [action] in [actionColor].
class FormFooter extends StatelessWidget {
  const FormFooter({
    super.key,
    required this.discard,
    required this.discardColor,
    required this.onDiscard,
    required this.onRefund,
    required this.action,
    required this.actionColor,
    required this.onAction,
    this.cancel = false,
  });

  final bool cancel;

  final String discard;
  final Color discardColor;
  final VoidCallback onDiscard;
  final VoidCallback? onRefund;
  final String action;
  final Color actionColor;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.s3,
        Space.s2,
        Space.s5,
        Space.s4,
      ),
      // With 取消 as well and the text grown large, the words take a row
      // of their own over the main button, which would not fit beside
      // them on a narrow phone.
      child: cancel && textGrowth(context) > 1.3
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: _words()),
                const SizedBox(height: Space.s2),
                _main(),
              ],
            )
          : Row(
              children: [
                ..._words(),
                const SizedBox(width: Space.s2),
                Expanded(child: _main()),
              ],
            ),
    );
  }

  List<Widget> _words() {
    final refund = onRefund;
    return [
      TextButton(
        key: Keys.discard,
        onPressed: onDiscard,
        style: wordButton(discardColor, minimumSize: Size(64, 48)),
        child: Text(discard),
      ),
      if (refund != null)
        TextButton(
          onPressed: refund,
          style: wordButton(AppColors.positive, minimumSize: Size(64, 48)),
          child: const Text(Words.refund),
        ),
      if (cancel) const CancelButton(word: true),
    ];
  }

  Widget _main() => SizedBox(
    height: 54,
    child: FilledButton(
      onPressed: onAction,
      key: Keys.save,
      style: solidButton(
        actionColor,
        radius: Radii.large,
        words: appFont.copyWith(
          fontSize: TextSize.title,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Text(action),
    ),
  );
}
