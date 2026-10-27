import 'package:flutter/material.dart';

import '../../../../core/look/widgets.dart';
import 'lock_parts.dart';

/// Restoring a ledger from a backup: the file, then that ledger's
/// password or recovery code.
class RestoreView extends StatelessWidget {
  const RestoreView({
    super.key,
    required this.file,
    required this.secret,
    required this.recovery,
    required this.busy,
    required this.onSubmit,
    required this.onToggleRecovery,
    this.onPickFile,
    this.onPickDrive,
    this.onBack,
    this.problem,
    this.about,
  });

  /// The backup's path: typed, or filled in by [onPickFile].
  final TextEditingController file;
  final TextEditingController secret;

  /// Whether [secret] is the recovery code rather than the password.
  final bool recovery;
  final bool busy;
  final VoidCallback onSubmit;
  final VoidCallback onToggleRecovery;

  /// Opens the system's file chooser; none where the path is typed.
  final VoidCallback? onPickFile;

  /// Chooses one of the backups on Google Drive; none off Android.
  final VoidCallback? onPickDrive;

  /// Back to the first screen; none when there is nothing to go back to.
  final VoidCallback? onBack;
  final String? problem;

  /// When the chosen backup was taken and what it holds.
  final String? about;

  @override
  Widget build(BuildContext context) {
    final pick = onPickFile;
    final drive = onPickDrive;
    final back = onBack;
    return LockForm(
      title: '從備份還原',
      hint: '輸入備份檔的位置，和那個帳本的密碼或救援碼。',
      fields: [
        if (pick != null)
          OutlinedButton(
            onPressed: busy ? null : pick,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
            child: Text(file.text.isEmpty ? '選擇備份檔' : '已選好備份檔'),
          )
        else
          PasswordField(
            controller: file,
            hint: '備份檔路徑，例如 C:\\Users\\me\\記帳本.etbk',
            hidden: false,
            boxed: true,
          ),
        if (about case final about?)
          Text(
            about,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13),
          ),
        if (drive != null)
          OutlinedButton(
            onPressed: busy ? null : drive,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
            child: const Text('從 Google 雲端硬碟選擇'),
          ),
        PasswordField(
          controller: secret,
          hint: recovery ? '救援碼' : '密碼',
          hidden: !recovery,
          boxed: true,
          onSubmitted: onSubmit,
        ),
      ],
      action: '還原',
      busy: busy,
      onSubmit: onSubmit,
      problem: problem,
      extras: [
        LockLink(recovery ? '改用密碼' : '忘記密碼？用救援碼', onToggleRecovery, busy: busy),
        if (back != null) LockLink('返回', back, busy: busy),
      ],
    );
  }
}
