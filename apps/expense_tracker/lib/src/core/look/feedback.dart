import 'package:flutter/material.dart';

import 'theme.dart';

/// Short feedback at the bottom, with an optional action.
void showNote(
  BuildContext context,
  String message, {
  String? action,
  VoidCallback? onAction,
}) {
  final act = onAction;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        // A note with an action (復原) would stay until swiped away; every
        // note goes by itself, a little later when it offers one.
        persist: false,
        duration: Duration(seconds: act == null ? 3 : 5),
        action: action == null || act == null
            ? null
            : SnackBarAction(
                label: action,
                textColor: Hue.selected,
                onPressed: act,
              ),
      ),
    );
}

/// Opens [builder] in a sheet from the bottom of the screen, full width,
/// as tall as its content and lifted over the keyboard. Every form and
/// picker in the app opens this way.
///
/// [capHeight] holds the sheet to three quarters of the screen at most,
/// its own content scrolling past that: for a sheet already built to
/// scroll internally (a [Flexible] or [Expanded] region around whatever
/// can grow long). Left off for one not yet checked against that.
Future<T?> showSheet<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool handle = true,
  bool capHeight = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: handle,
    backgroundColor: Hue.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (context) {
      final child = Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: builder(context),
      );
      if (!capHeight) return child;
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: child,
      );
    },
  );
}
