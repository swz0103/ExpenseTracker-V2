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
Future<T?> showSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Hue.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: builder(context),
    ),
  );
}
