import 'package:flutter/material.dart';

import '../../../core/design_system/findable.dart';
import '../../../core/formatting/setting_topic.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/messages/backup_messages.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/design_system/shape.dart';

/// A setting on a [BackupCard]: its name, and on the right its value
/// with › or a control.
class BackupCardRow extends StatelessWidget {
  const BackupCardRow({
    super.key,
    required this.color,
    required this.title,
    this.detail,
    this.value,
    this.trailing,
    this.onTap,
  });

  final Color color;
  final String title;
  final String? detail;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = deepOf(color);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.medium),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  OneLine(
                    title,
                    style: TextStyle(
                      fontSize: TextSize.body,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  if (detail != null)
                    Text(
                      detail!,
                      style: TextStyle(fontSize: TextSize.caption, color: ink),
                    ),
                ],
              ),
            ),
            if (value != null)
              Padding(
                padding: const EdgeInsets.only(right: Space.s2),
                child: OneLine(
                  '${value!} ›',
                  style: TextStyle(fontWeight: FontWeight.w700, color: ink),
                ),
              ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// The folder card's notice that the folder chosen no longer lets the app
/// write, with 重新選擇, which opens the chooser again.
class FolderDeniedRow extends StatelessWidget {
  const FolderDeniedRow({
    super.key,
    required this.color,
    required this.onChoose,
  });

  final Color color;
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    final ink = deepOf(color);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          Expanded(
            child: Text(
              BackupWords.folderDenied,
              style: TextStyle(
                fontSize: TextSize.body,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
          ),
          TextButton(
            key: Keys.chooseFolderAgain,
            style: wordButton(ink),
            onPressed: onChoose,
            child: const Text(BackupWords.chooseFolderAgain),
          ),
        ],
      ),
    );
  }
}

/// A way of backing up as a tinted card: its icon, name and tick, then
/// its settings below thin rules, each with its value on the right.
class BackupCard extends StatelessWidget {
  const BackupCard({
    super.key,
    required this.topic,
    required this.glyph,
    required this.color,
    required this.title,
    required this.value,
    required this.onChanged,
    required this.rows,
  });

  final SettingTopic topic;
  final Glyph glyph;
  final Color color;
  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final change = onChanged;
    return Findable(
      topic: topic,
      child: ColorCard(
        controlsInside: true,
        color: color,
        padding: const EdgeInsets.fromLTRB(
          Space.s4,
          Space.s3,
          Space.s2,
          Space.s3,
        ),
        child: Column(
          children: [
            ToggleRow(
              value: value,
              onChanged: change,
              label: title,
              child: Row(
                children: [
                  SquareIcon(glyph, color, size: 40),
                  const SizedBox(width: Space.s4),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: TextSize.title,
                        fontWeight: FontWeight.w800,
                        color: deepOf(color),
                      ),
                    ),
                  ),
                  TickSwitch(
                    value: value,
                    color: color,
                    label: title,
                    onChanged: change,
                  ),
                ],
              ),
            ),
            for (final row in rows) ...[
              Padding(
                padding: const EdgeInsets.only(right: Space.s2),
                child: Divider(height: 12, color: tintOf(color, 0.4)),
              ),
              row,
            ],
          ],
        ),
      ),
    );
  }
}
