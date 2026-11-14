import 'package:flutter/material.dart';

import '../../../core/look/theme.dart';
import '../model/app_update.dart';

/// A newer version: its name and what it changes in a few lines, with
/// 稍後 and 更新. 更新 downloads it in the same panel, a bar filling, and
/// hands it to Android's installer; nothing else is asked or said unless
/// something goes wrong.
Future<void> showUpdatePanel(BuildContext context, AppUpdate update) async {
  final info = update.newer;
  if (info == null) return;
  await showDialog<void>(
    context: context,
    barrierColor: const Color(0x66222B30),
    builder: (context) => _UpdatePanel(update: update, info: info),
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
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
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                for (final line in info.notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '・',
                          style: TextStyle(fontSize: 15, color: Hue.accent),
                        ),
                        Expanded(
                          child: Text(
                            line,
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (info.notes.isEmpty)
                  const Text(
                    '修正與改進',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: Hue.muted),
                  ),
                if (_problem case final problem?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      problem,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, color: Hue.negative),
                    ),
                  ),
                const SizedBox(height: 18),
                if (progress != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      color: Hue.accent,
                      backgroundColor: Hue.surface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '下載中 ${(progress * 100).round()}%',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: Hue.muted),
                  ),
                ] else
                  Row(
                    children: [
                      Expanded(
                        child: _Choice(
                          '稍後',
                          color: Hue.surface,
                          ink: Hue.ink,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Choice(
                          '更新',
                          color: Hue.positive,
                          ink: Hue.onAccent,
                          onTap: widget.update.busy ? null : _install,
                        ),
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice(
    this.label, {
    required this.color,
    required this.ink,
    this.onTap,
  });

  final String label;
  final Color color;
  final Color ink;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: ink,
        minimumSize: const Size(0, 52),
        textStyle: appFont.copyWith(fontSize: 16, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(label),
    );
  }
}
