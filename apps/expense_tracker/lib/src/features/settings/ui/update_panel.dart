import 'package:flutter/material.dart';

import '../../../core/look/theme.dart';
import '../model/app_update.dart';
import '../../../core/look/kit/buttons.dart';
import '../../../core/look/keys.dart';
import '../../../core/look/shape.dart';
import '../../../core/look/spacing.dart';

/// A newer version: its name and what it changes in a few lines, with
/// 更新, and 晚一點再說 or 略過這一版 under it. Only these close it: not a
/// tap beside it nor back, so it is not lost by a slip on opening the
/// app. 更新 downloads it in the same panel, a bar filling, and hands it
/// to Android's installer; nothing else is asked or said unless
/// something goes wrong.
Future<void> showUpdatePanel(BuildContext context, AppUpdate update) async {
  final info = update.newer;
  if (info == null) return;
  await showDialog<void>(
    context: context,
    barrierColor: Hue.scrim,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: _UpdatePanel(update: update, info: info),
    ),
  );
}

class _UpdatePanel extends StatefulWidget {
  const _UpdatePanel({required this.update, required this.info});

  final AppUpdate update;
  final UpdateInfo info;

  @override
  State<_UpdatePanel> createState() => _UpdatePanelState();
}

class _UpdatePanelState extends State<_UpdatePanel> {
  /// What went wrong, in place of the notes' end; null while all is well.
  String? _problem;

  Future<void> _install() async {
    setState(() => _problem = null);
    final outcome = await widget.update.install();
    if (!mounted) return;
    switch (outcome) {
      case UpdateInstall.started:
        Navigator.of(context).pop();
      case UpdateInstall.needsPermission:
        setState(() => _problem = '請允許「記帳本」安裝應用程式，回來後再按一次更新');
      case UpdateInstall.damaged:
      case null:
        setState(() => _problem = widget.update.problem ?? '下載失敗，請稍後再試');
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return Dialog(
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
        child: ListenableBuilder(
          listenable: widget.update,
          builder: (context, _) {
            final progress = widget.update.progress;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '新版 ${info.name}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: TextSize.heading,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: Space.s4),
                for (final line in info.notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.s2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '・',
                          style: TextStyle(
                            fontSize: TextSize.body,
                            color: Hue.accent,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            line,
                            style: const TextStyle(fontSize: TextSize.body),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (info.notes.isEmpty)
                  const Text(
                    '修正與改進',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: TextSize.body, color: Hue.muted),
                  ),
                if (_problem case final problem?)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.s2),
                    child: Text(
                      problem,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: TextSize.body,
                        color: Hue.negative,
                      ),
                    ),
                  ),
                const SizedBox(height: Space.s4),
                if (progress != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.extraSmall),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      color: Hue.accent,
                      backgroundColor: Hue.surface,
                    ),
                  ),
                  const SizedBox(height: Space.s2),
                  Text(
                    '下載中 ${(progress * 100).round()}%',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: TextSize.body,
                      color: Hue.muted,
                    ),
                  ),
                ] else ...[
                  _Choice(
                    '更新',
                    key: Keys.install,
                    color: Hue.positive,
                    onTap: widget.update.busy ? null : _install,
                  ),
                  const SizedBox(height: Space.s2),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          key: Keys.later,
                          style: wordButton(Hue.muted),
                          onPressed: () {
                            widget.update.later();
                            Navigator.of(context).pop();
                          },
                          child: const Text('晚一點再說'),
                        ),
                      ),
                      Expanded(
                        child: TextButton(
                          key: Keys.skip,
                          style: wordButton(Hue.muted),
                          onPressed: () {
                            widget.update.skip(info);
                            Navigator.of(context).pop();
                          },
                          child: const Text('略過這一版'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice(this.label, {super.key, required this.color, this.onTap});

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: solidButton(
        color,
        minimumSize: Size(0, 52),
        radius: Radii.large,
        words: appFont.copyWith(
          fontSize: TextSize.title,
          fontWeight: FontWeight.w800,
        ),
      ),
      child: Text(label),
    );
  }
}
