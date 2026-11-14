import 'package:flutter/material.dart';

import '../controls.dart';
import '../glyphs.dart';
import '../theme.dart';
import '../kit.dart';

// The panel in the middle of the screen and its buttons.

/// The panel in the middle of the screen that every setting's details
/// open in, never a sheet from the bottom: its icon, name and a line on
/// what it does at the top, [trailing] on the right of that, then [body]
/// and the [actions] along the bottom.
class CenterPanel extends StatelessWidget {
  const CenterPanel({
    super.key,
    required this.glyph,
    required this.color,
    required this.title,
    this.detail,
    this.trailing,
    this.body,
    this.actions = const [],
  });

  final Glyph glyph;
  final Color color;
  final String title;
  final String? detail;
  final Widget? trailing;
  final Widget? body;

  /// Buttons side by side along the bottom, each as wide as the others.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Hue.paper,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SquareIcon(glyph, color, size: 56),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (detail != null)
                        Text(
                          detail!,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Hue.muted,
                          ),
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            if (body != null) ...[const SizedBox(height: 18), body!],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  for (final (i, action) in actions.indexed) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: action),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Opens a [CenterPanel] with 完成 along the bottom and, when [value] is
/// given, a [TickSwitch] at the top. A tap on the dark around it closes
/// it as well. [body] is built again after the switch is touched.
Future<void> showCenterPanel(
  BuildContext context, {
  required Glyph glyph,
  required Color color,
  required String title,
  String? detail,
  bool Function()? value,
  ValueChanged<bool>? onChanged,
  WidgetBuilder? body,
  String done = '完成',
}) {
  return showPanel<void>(
    context,
    (context) => StatefulBuilder(
      builder: (context, setState) {
        final on = value?.call();
        return CenterPanel(
          glyph: glyph,
          color: color,
          title: title,
          detail: detail,
          trailing: on == null
              ? null
              : TickSwitch(
                  value: on,
                  color: color,
                  label: title,
                  onChanged: onChanged == null
                      ? null
                      : (v) {
                          onChanged(v);
                          setState(() {});
                        },
                ),
          body: body == null ? null : Builder(builder: body),
          actions: [
            PanelButton(done, onTap: () => Navigator.of(context).pop()),
          ],
        );
      },
    ),
  );
}

/// Opens [builder] over a dimmed page, as the middle-of-the-screen panels
/// are; a tap on the dark closes it unless [dismissible] is off.
Future<T?> showPanel<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool dismissible = true,
}) => showDialog<T>(
  context: context,
  barrierDismissible: dismissible,
  barrierColor: const Color(0x66222B30),
  builder: builder,
);

/// A wide button: grey by default, solid [color] when given.
class PanelButton extends StatelessWidget {
  const PanelButton(
    this.label, {
    super.key,
    required this.onTap,
    this.color,
    this.tinted = false,
  });

  final String label;
  final VoidCallback? onTap;
  final Color? color;

  /// On [color]'s tint with its deeper words, not solid: one of a row of
  /// plain actions, such as 買進, 賣出 and 記股息.
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final solid = color;
    return Pressable(
      child: Material(
        color: solid == null
            ? Hue.surface
            : tinted
            ? tintOf(solid, 0.22)
            : solid,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: solid == null
                        ? Hue.ink
                        : tinted
                        ? deepOf(solid)
                        : Hue.onAccent,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
