import 'package:flutter/material.dart';

import '../../../../core/look/widgets.dart';
import 'lock_parts.dart';

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
  });

  final TextEditingController code;
  final bool busy;
  final VoidCallback onSubmit;

  /// Back to the password: 改用密碼.
  final VoidCallback onPassword;

  /// Back to the first screen; none when there is nothing to go back to.
  final VoidCallback? onBack;
  final String? problem;

  @override
  Widget build(BuildContext context) {
    final back = onBack;
    return LockForm(
      title: '打開帳本',
      hint: '輸入建立帳本時拿到的救援碼。',
      fields: [
        PasswordField(
          controller: code,
          hint: '救援碼',
          hidden: false,
          boxed: true,
          onSubmitted: onSubmit,
        ),
      ],
      action: '打開',
      busy: busy,
      onSubmit: onSubmit,
      problem: problem,
      extras: [
        LockLink('改用密碼', onPassword, busy: busy),
        if (back != null) LockLink('返回', back, busy: busy),
      ],
    );
  }
}
