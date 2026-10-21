import 'package:flutter/material.dart';

import '../../look/widgets.dart';
import 'lock_parts.dart';

/// Opening a ledger with its password, or with a fingerprint or face
/// when the phone can.
class UnlockView extends StatelessWidget {
  const UnlockView({
    super.key,
    required this.password,
    required this.busy,
    required this.onSubmit,
    required this.onRecovery,
    this.onDevice,
    this.onBack,
    this.problem,
  });

  final TextEditingController password;
  final bool busy;
  final VoidCallback onSubmit;

  /// Uses the recovery code instead: 忘記密碼.
  final VoidCallback onRecovery;

  /// Asks for the fingerprint or face; none when the phone cannot.
  final VoidCallback? onDevice;

  /// Back to the first screen; none when there is nothing to go back to.
  final VoidCallback? onBack;
  final String? problem;

  @override
  Widget build(BuildContext context) {
    final device = onDevice;
    final back = onBack;
    return LockForm(
      title: '打開帳本',
      hint: '輸入帳本密碼。',
      fields: [
        PasswordField(
          controller: password,
          hint: '密碼',
          boxed: true,
          onSubmitted: onSubmit,
        ),
      ],
      action: '打開',
      busy: busy,
      onSubmit: onSubmit,
      problem: problem,
      extras: [
        LockLink('忘記密碼？用救援碼', onRecovery, busy: busy),
        if (device != null) LockLink('用指紋或臉部解鎖', device, busy: busy),
        if (back != null) LockLink('返回', back, busy: busy),
      ],
    );
  }
}
