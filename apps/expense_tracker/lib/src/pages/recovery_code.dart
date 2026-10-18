import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows a new ledger's recovery code once; it is the only way in without
/// the password.
Future<void> showRecoveryCode(
  BuildContext context,
  String code, {
  String why = '忘記密碼時，只有這組救援碼能打開帳本。請抄下來放在安全的地方，它只會顯示這一次。',
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('救援碼'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(why),
          const SizedBox(height: 14),
          SelectableText(
            code,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Clipboard.setData(ClipboardData(text: code)),
          child: const Text('複製'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('我已存好'),
        ),
      ],
    ),
  );
}
