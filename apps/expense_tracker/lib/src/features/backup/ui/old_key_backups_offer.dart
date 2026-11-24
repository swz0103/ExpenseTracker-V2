import 'package:flutter/material.dart';

import '../../../../design_system/display/date.dart';
import '../../../core/design_system/feedback.dart';
import '../../../core/design_system/dialogs.dart';
import '../../../core/messages/key_messages.dart';
import '../model/old_key_backups.dart';

/// After a reset of the keys (D15): finds the backups still sealed with
/// the old ones, lists how many and their dates on Drive and on the
/// phone, and takes them away only once the person confirms.
Future<void> offerToRemoveOldKeyBackups(
  BuildContext context,
  OldKeyBackups old,
) async {
  final found = await old.find();
  if (!context.mounted) return;
  if (found.isEmpty) {
    if (found.driveUnreached) showNote(context, KeyWords.oldBackupsUnreached);
    return;
  }
  final sure = await confirm(
    context,
    KeyWords.oldBackupsTitle,
    KeyWords.oldBackupsGo,
    danger: true,
    body: KeyWords.oldBackupsBody(
      drive: [for (final f in found.drive) formatYMd(f.modified.toLocal())],
      phone: [for (final (_, at) in found.local) formatYMd(at.toLocal())],
      driveUnreached: found.driveUnreached,
    ),
  );
  if (!sure) return;
  final gone = await old.remove(found);
  if (context.mounted) showNote(context, KeyWords.oldBackupsGone(gone));
}
