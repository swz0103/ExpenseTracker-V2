import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../look/theme.dart';

/// Blurs everything the app shows, sheets and dialogs included, while it
/// is off the screen, so the recent apps list shows no amount. Put above
/// every route (MaterialApp's builder).
///
/// When [systemHides] answers true (Android 13 and later keep the app's
/// screen out of the recent apps list themselves), nothing is blurred: a
/// screenshot or the notification shade does not cover the app either.
class PrivacyCover extends StatefulWidget {
  const PrivacyCover({super.key, required this.child, this.systemHides});

  final Widget child;
  final Future<bool> Function()? systemHides;

  @override
  State<PrivacyCover> createState() => _PrivacyCoverState();
}

class _PrivacyCoverState extends State<PrivacyCover>
    with WidgetsBindingObserver {
  var _covered = false;

  /// Blurred while away; false once the phone says it hides the app.
  var _needed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_ask());
  }

  Future<void> _ask() async {
    final ask = widget.systemHides;
    if (ask == null) return;
    try {
      if (await ask() && mounted) {
        setState(() {
          _needed = false;
          _covered = false;
        });
      }
    } on Object {
      // Kept blurring: the safe way when the phone cannot say.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_needed) return;
    // Blurred from inactive on, before the phone takes the picture for
    // the recent apps list.
    final covered = state != AppLifecycleState.resumed;
    if (covered != _covered) setState(() => _covered = covered);
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.child,
      if (_covered)
        ClipRect(
          child: BackdropFilter(
            key: const ValueKey('privacy-blur'),
            filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: ColoredBox(color: Hue.paper.withValues(alpha: 0.45)),
          ),
        ),
    ],
  );
}
