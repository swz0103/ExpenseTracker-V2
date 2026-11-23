import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';
import 'keys.dart';
import 'shape.dart';

/// The app's one place for notes at the bottom (`MaterialApp`'s
/// `scaffoldMessengerKey`), so one can be shown from where there is no
/// screen at hand: [showNoteAnywhere].
final appMessenger = GlobalKey<ScaffoldMessengerState>();

/// Short feedback at the bottom, with an optional action.
void showNote(
  BuildContext context,
  String message, {
  String? action,
  VoidCallback? onAction,
  String? spoken,
}) => _note(
  ScaffoldMessenger.of(context),
  message,
  action: action,
  onAction: onAction,
  spoken: spoken,
);

/// [showNote] from code that has no screen of its own, such as what
/// answers a fault nobody caught: said over whatever screen is open.
/// False when the app has nowhere to say it yet.
bool showNoteAnywhere(String message) {
  final messenger = appMessenger.currentState;
  if (messenger == null) return false;
  _note(messenger, message);
  return true;
}

void _note(
  ScaffoldMessengerState messenger,
  String message, {
  String? action,
  VoidCallback? onAction,
  String? spoken,
}) {
  final act = onAction;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, semanticsLabel: spoken),
        // A note with an action (復原) would stay until swiped away; every
        // note goes by itself, a little later when it offers one.
        persist: false,
        // Exception to motion: how long the note stays to be read, not a
        // movement; reduced motion must not make it vanish.
        duration: Duration(seconds: act == null ? 3 : 5),
        action: action == null || act == null
            ? null
            : SnackBarAction(
                key: Keys.snack(action),
                label: action,
                textColor: Shade.dark ? AppColors.accent : AppColors.selected,
                onPressed: act,
              ),
      ),
    );
}

/// Opens [builder] in a sheet from the bottom of the screen, full width,
/// as tall as its content and lifted over the keyboard. Every form and
/// picker in the app opens this way.
///
/// `capHeight` holds the sheet to three quarters of the screen at most,
/// its own content scrolling past that: for a sheet already built to
/// scroll internally (a [Flexible] or [Expanded] region around whatever
/// can grow long). Left off for one not yet checked against that.
///
/// `height` instead makes the sheet that share of the screen however
/// much it holds, as [sheetHeight] for the pickers 記一筆 opens: one
/// picker after another, the sheet stays put. Its content fills it, and
/// scrolls inside it when longer.
/// Opens [builder] as a task over the whole screen with its own 取消 and
/// 完成, such as 排序帳戶 or 匯入: not a place to go back to, so not one
/// of the app frame's pages. The one way the app pushes a route itself.
Future<T?> openFullScreen<T>(BuildContext context, WidgetBuilder builder) =>
    Navigator.of(
      context,
    ).push<T>(MaterialPageRoute<T>(fullscreenDialog: true, builder: builder));

Future<T?> showSheet<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool handle = true,
  bool capHeight = false,
  double? height,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: handle,
    backgroundColor: AppColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(Radii.largeIncreased),
      ),
    ),
    builder: (context) {
      final share = height;
      final screen = MediaQuery.sizeOf(context).height;
      final inset = MediaQuery.viewInsetsOf(context).bottom;
      final child = Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: share == null
            ? builder(context)
            : SizedBox(
                height: math.max(
                  0.0,
                  math.min(screen * share, screen * 0.9 - inset),
                ),
                child: builder(context),
              ),
      );
      if (!capHeight || share != null) return child;
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: child,
      );
    },
  );
}

/// The share of the screen the pickers 記一筆 opens take, all alike so
/// the sheet does not jump from one to the next.
const sheetHeight = 0.62;
