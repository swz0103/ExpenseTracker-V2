import 'package:flutter/material.dart';

import '../look/theme.dart';

/// Covers everything the app shows, sheets and dialogs included, while it
/// is off the screen, so the recent apps list shows the app's name and
/// not an amount. Put above every route (MaterialApp's builder).
class PrivacyCover extends StatefulWidget {
  const PrivacyCover({super.key, required this.child});

  final Widget child;

  @override
  State<PrivacyCover> createState() => _PrivacyCoverState();
}

class _PrivacyCoverState extends State<PrivacyCover>
    with WidgetsBindingObserver {
  var _covered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Covered from inactive on, before the phone takes the picture for
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
        const ColoredBox(
          color: Hue.panel,
          child: Center(
            child: Text(
              '記帳本',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Hue.muted,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
    ],
  );
}
