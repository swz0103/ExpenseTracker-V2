import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';
import 'lock_parts.dart';
import '../../../../core/formatting/words.dart';

/// Opening a ledger with the recovery code given when it was made, when
/// the password is forgotten. The code is shown as typed: it is read off
/// paper.
class RecoveryView extends StatelessWidget {
  const RecoveryView({
    super.key,
    required this.code,
    required this.busy,
    required this.onSubmit,
    required this.onPassword,
    this.onBack,
    this.problem,
    this.waiting,
    this.hint = '輸入建立帳本時拿到的救援碼。',
    this.codeLabel = '救援碼',
  });

  final TextEditingController code;
  final bool busy;
  final VoidCallback onSubmit;

  /// Back to the password: 改用密碼.
  final VoidCallback onPassword;

  /// Back to the first screen; none when there is nothing to go back to.
  final VoidCallback? onBack;
  final String? problem;

  /// Said in place of [problem] while the code may not be typed: the wait
  /// after too many wrong ones, counting down.
  final String? waiting;

  /// What the form asks for, said under its title.
  final String hint;

  /// The words in the field, such as 救援碼或備份密碼.
  final String codeLabel;

  @override
  Widget build(BuildContext context) {
    final back = onBack;
    return LockForm(
      title: '打開帳本',
      hint: hint,
      fields: [
        PasswordField(
          controller: code,
          hint: codeLabel,
          boxed: true,
          enabled: waiting == null,
          onSubmitted: onSubmit,
        ),
      ],
      action: '打開',
      busy: busy,
      onSubmit: onSubmit,
      problem: problem,
      waiting: waiting,
      extras: [
        LockLink('改用密碼', onPassword, busy: busy),
        if (back != null)
          LockLink(Words.back, back, busy: busy, key: Keys.back),
      ],
    );
  }
}
