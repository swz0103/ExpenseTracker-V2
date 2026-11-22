import 'package:flutter/material.dart';

import '../../../../core/design_system/theme.dart';
import '../../../../core/design_system/design_system.dart';
import 'lock_parts.dart';
import '../../../../core/formatting/words.dart';

/// Restoring a ledger from a backup: the file, then what opens it, as
/// the backup chosen says ([hint]): its recovery code or backup
/// passphrase, or for an older backup its ledger's password too.
class RestoreView extends StatelessWidget {
  const RestoreView({
    super.key,
    required this.file,
    required this.secret,
    required this.recovery,
    required this.busy,
    required this.onSubmit,
    this.onToggleRecovery,
    this.onPickFile,
    this.onPickDrive,
    this.onBack,
    this.problem,
    this.about,
    this.onPickKept,
    this.hint = '輸入備份檔的位置，和那個帳本的密碼或救援碼。',
    this.codeLabel = '救援碼',
  });

  /// The backup's path: typed, or filled in by [onPickFile].
  final TextEditingController file;
  final TextEditingController secret;

  /// Whether [secret] is the recovery code rather than the password.
  final bool recovery;
  final bool busy;
  final VoidCallback onSubmit;

  /// Between the password and the recovery code; none when the backup
  /// chosen has no password to open it with.
  final VoidCallback? onToggleRecovery;

  /// What the form asks for, said under its title.
  final String hint;

  /// The words in the field for the recovery code, such as 救援碼或備份密碼.
  final String codeLabel;

  /// Opens the system's file chooser; none where the path is typed.
  final VoidCallback? onPickFile;

  /// Chooses one of the backups on Google Drive; none off Android.
  final VoidCallback? onPickDrive;

  /// Back to the first screen; none when there is nothing to go back to.
  final VoidCallback? onBack;
  final String? problem;

  /// When the chosen backup was taken and what it holds.
  final String? about;

  /// Chooses the ledger kept before an earlier restore; none when there
  /// is none.
  final VoidCallback? onPickKept;

  @override
  Widget build(BuildContext context) {
    final pick = onPickFile;
    final drive = onPickDrive;
    final back = onBack;
    return LockForm(
      title: '從備份還原',
      hint: hint,
      fields: [
        if (pick != null)
          FilledButton(
            onPressed: busy ? null : pick,
            style: _choice,
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
            style: const TextStyle(fontSize: TextSize.small),
          ),
        if (drive != null)
          FilledButton(
            onPressed: busy ? null : drive,
            style: _choice,
            child: const Text('從 Google 雲端硬碟選擇'),
          ),
        if (onPickKept case final kept?)
          FilledButton(
            onPressed: busy ? null : kept,
            style: _choice,
            child: const Text('還原前自動留下的帳本'),
          ),
        PasswordField(
          controller: secret,
          hint: recovery ? codeLabel : '密碼',
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
        if (onToggleRecovery case final toggle?)
          LockLink(recovery ? '改用密碼' : '忘記密碼？用救援碼', toggle, busy: busy),
        if (back != null)
          LockLink(Words.back, back, busy: busy, key: Keys.back),
      ],
    );
  }
}

/// A way to find the backup: a quiet button the width of the form.
final _choice = solidButton(
  AppColors.surface,
  ink: AppColors.accent,
  minimumSize: const Size.fromHeight(44),
);
