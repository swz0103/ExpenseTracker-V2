import 'package:flutter/material.dart';

import '../../../backup/model/keeper.dart';
import '../../../../core/look/dialogs.dart';
import '../../../../core/look/glyphs.dart';
import '../../../../core/look/theme.dart';
import '../../../../core/look/widgets.dart';
import '../../../../core/problems.dart';
import '../../../../core/screen_privacy.dart';
import '../../../lock/ui/recovery_code.dart';

/// 安全: the ledger's password and recovery code, hiding the screens,
/// and locking the ledger again.
class SecuritySection extends StatefulWidget {
  const SecuritySection({super.key, this.keeper, this.privacy});

  final Keeper? keeper;
  final ScreenPrivacy? privacy;

  @override
  State<SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<SecuritySection> {
  Future<void> _changePassword(Keeper keeper) async {
    final first = !keeper.hasPassword;
    final passwords = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _PasswordDialog(first: first),
    );
    if (passwords == null) return;
    final (current, next) = passwords;
    try {
      if (first) {
        await keeper.setPassword(next);
        // A ledger started without a password has had no code to show yet.
        final code = await keeper.newRecoveryCode();
        if (mounted) {
          await showRecoveryCode(
            context,
            code,
            why: '密碼設好了。忘記密碼時，只有這組救援碼能打開帳本。請抄下來放在安全的地方，它只會顯示這一次。',
          );
        }
      } else {
        await keeper.changePassword(current, next);
      }
      if (mounted) setState(() {});
      if (mounted) showNote(context, first ? '已設定密碼' : '密碼已變更');
    } on Object catch (error) {
      if (!mounted) return;
      final wrong = '$error'.contains('wrongSecret');
      final weak = '$error'.contains('weakPassword');
      showNote(
        context,
        wrong
            ? '目前的密碼不正確'
            : weak
            ? '新密碼至少要 6 個字'
            : '無法變更密碼（$error）',
      );
    }
  }

  Future<void> _newRecovery(Keeper keeper) async {
    final ok = await confirm(context, '換一組新的救援碼？舊的會立刻失效。', '更換');
    if (!ok) return;
    try {
      final code = await keeper.newRecoveryCode();
      if (mounted) await showRecoveryCode(context, code);
    } on Object catch (error) {
      if (mounted) showNote(context, '沒有換成：${describeProblem(error)}');
    }
  }

  /// Turns screen hiding on or off.
  Future<void> _hideScreen(ScreenPrivacy privacy, bool on) async {
    try {
      await privacy.turn(on: on);
    } on Object {
      if (mounted) showNote(context, '這支手機無法切換截圖設定');
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final keeper = widget.keeper;
    final privacy = widget.privacy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MenuPanel([
          if (keeper != null) ...[
            MenuRow(
              glyph: Glyph.shield,
              title: keeper.hasPassword ? '變更密碼' : '設定密碼',
              detail: keeper.hasPassword ? '已設定' : '目前不用密碼',
              onTap: () => _changePassword(keeper),
            ),
            MenuRow(
              glyph: Glyph.ticket,
              title: keeper.hasPassword ? '更換救援碼' : '取得救援碼',
              detail: '換手機還原用',
              onTap: () => _newRecovery(keeper),
            ),
          ],
          if (privacy != null)
            MenuRow(
              glyph: Glyph.eyeOff,
              title: '不讓截圖',
              detail: '最近使用的 App 也看不到',
              trailing: Switch(
                value: privacy.on,
                onChanged: (on) => _hideScreen(privacy, on),
              ),
            ),
          if (keeper != null && keeper.hasPassword)
            MenuRow(
              glyph: Glyph.close,
              title: '鎖定帳本',
              detail: '回到解鎖畫面',
              onTap: keeper.lock,
            ),
        ]),
      ],
    );
  }
}

/// Asks for the current password and a new one twice; returns the
/// current and the new one.
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.first});

  /// Setting a password on a ledger that has none: nothing to confirm.
  final bool first;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  void _submit() {
    if (_next.text != _again.text) {
      setState(() => _problem = '兩次輸入的新密碼不一樣');
      return;
    }
    Navigator.of(context).pop((_current.text, _next.text));
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController controller, String hint) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PasswordField(controller: controller, hint: hint),
    );
    final first = widget.first;
    return AlertDialog(
      title: Text(first ? '設定密碼' : '變更密碼'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!first) field(_current, '目前的密碼'),
          field(_next, '新密碼'),
          field(_again, '再輸入一次新密碼'),
          if (_problem case final problem?)
            Text(problem, style: const TextStyle(color: Hue.danger)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: Text(first ? '設定' : '變更')),
      ],
    );
  }
}
