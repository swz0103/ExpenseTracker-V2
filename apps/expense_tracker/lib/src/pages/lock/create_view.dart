import 'package:flutter/material.dart';

import '../../look/widgets.dart';
import 'lock_parts.dart';

/// A new ledger with a password: typed twice, then 建立.
class CreateView extends StatelessWidget {
  const CreateView({
    super.key,
    required this.password,
    required this.again,
    required this.busy,
    required this.onSubmit,
    this.onBack,
    this.problem,
  });

  final TextEditingController password;
  final TextEditingController again;
  final bool busy;
  final VoidCallback onSubmit;

  /// Back to the first screen; none when there is nothing to go back to.
  final VoidCallback? onBack;
  final String? problem;

  @override
  Widget build(BuildContext context) {
    final back = onBack;
    return LockForm(
      title: '建立帳本',
      hint: '帳本會以這組密碼加密，只存在這台裝置上。至少 6 個字。',
      fields: [
        PasswordField(controller: password, hint: '密碼', boxed: true),
        PasswordField(
          controller: again,
          hint: '再輸入一次密碼',
          boxed: true,
          onSubmitted: onSubmit,
        ),
      ],
      action: '建立',
      busy: busy,
      onSubmit: onSubmit,
      problem: problem,
      extras: [if (back != null) LockLink('返回', back, busy: busy)],
    );
  }
}
