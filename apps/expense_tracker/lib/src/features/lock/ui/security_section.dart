import 'package:flutter/material.dart';

import '../../backup/model/backup_manager.dart';
import '../../../core/design_system/dialogs.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/messages/problem_messages.dart';
import '../../../core/platform/screen_privacy.dart';
import '../../../core/design_system/recovery_code.dart';
import '../../../core/design_system/settings_hue.dart';
import '../../../core/diagnostics/error_log.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/formatting/words.dart';

/// 安全: four cards: the password, the recovery code, hiding the screens,
/// and locking the ledger now.
class SecuritySection extends StatefulWidget {
  const SecuritySection({super.key, this.backupManager, this.privacy});

  final BackupManager? backupManager;
  final ScreenPrivacy? privacy;

  @override
  State<SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<SecuritySection> {
  Future<void> _changePassword(BackupManager backupManager) async {
    final first = !backupManager.hasPassword;
    final passwords = await showPanel<(String, String)>(
      context,
      (_) => _PasswordPanel(first: first),
    );
    if (passwords == null) return;
    final (current, next) = passwords;
    try {
      if (first) {
        await backupManager.setPassword(next);
        // A ledger started without a password has had no code to show yet.
        final code = await backupManager.newRecoveryCode();
        if (mounted) {
          await showRecoveryCode(context, code, why: '密碼設好了。忘記密碼時，只有它能打開帳本');
        }
      } else {
        await backupManager.changePassword(current, next);
      }
      if (mounted) setState(() {});
      if (mounted) showNote(context, first ? '已設定密碼' : '密碼已變更');
    } on Object catch (error) {
      // A wrong or weak password is said to the person, by its kind.
      if (!mounted) return;
      final wrong = '$error'.contains('wrongSecret');
      final weak = '$error'.contains('weakPassword');
      showNote(
        context,
        wrong
            ? '目前的密碼不正確'
            : weak
            ? '新密碼至少要 6 個字'
            : '無法變更密碼（${ErrorLog.describe(error)}）',
      );
    }
  }

  Future<void> _newRecovery(BackupManager backupManager) async {
    final ok = await confirm(context, '換一組新的？舊的會立刻失效', '更換');
    if (!ok) return;
    try {
      final code = await backupManager.newRecoveryCode();
      if (mounted) await showRecoveryCode(context, code);
    } on Object catch (error) {
      ErrorLog.instance.record('變更密碼', error);
      if (mounted) showNote(context, '沒有換成：${describeProblem(error)}');
    }
  }

  /// Turns screen hiding on or off.
  Future<void> _hideScreen(ScreenPrivacy privacy, bool on) async {
    try {
      await privacy.turn(on: on);
    } on Object catch (error) {
      ErrorLog.instance.record('截圖設定', error);
      if (mounted) showNote(context, '這支手機無法切換截圖設定');
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final backupManager = widget.backupManager;
    final privacy = widget.privacy;
    return CardGrid([
      if (backupManager != null) ...[
        SettingCard(
          key: Keys.password,
          glyph: Glyph.key,
          color: SettingsHue.password,
          title: '密碼',
          detail: backupManager.hasPassword ? '已設定 · 點了變更' : '還沒設定 · 點了設定',
          onTap: () => _changePassword(backupManager),
        ),
        SettingCard(
          glyph: Glyph.lifebuoy,
          color: SettingsHue.recovery,
          title: '救援碼',
          detail: '忘記密碼、換手機用',
          onTap: () => _newRecovery(backupManager),
        ),
      ],
      if (privacy != null)
        SettingCard(
          glyph: Glyph.eyeOff,
          color: SettingsHue.appearance,
          title: '不讓截圖',
          detail: '最近使用的 App 也看不到',
          value: privacy.on,
          onChanged: (on) => _hideScreen(privacy, on),
          onTap: () => _hideScreen(privacy, !privacy.on),
        ),
      if (backupManager != null && backupManager.hasPassword)
        SettingCard(
          key: Keys.lockNow,
          glyph: Glyph.lock,
          color: SettingsHue.about,
          title: '現在鎖上',
          detail: '回到解鎖畫面',
          onTap: backupManager.lock,
        ),
    ]);
  }
}

/// Asks for the current password and a new one twice; returns the
/// current and the new one.
class _PasswordPanel extends StatefulWidget {
  const _PasswordPanel({required this.first});

  /// Setting a password on a ledger that has none: nothing to confirm.
  final bool first;

  @override
  State<_PasswordPanel> createState() => _PasswordPanelState();
}

class _PasswordPanelState extends State<_PasswordPanel> {
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
    const color = SettingsHue.password;
    Widget field(TextEditingController controller, String label) => Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          Space.s4,
          Space.s2,
          Space.s4,
          Space.s1,
        ),
        decoration: BoxDecoration(
          color: tintOf(color, 0.14),
          borderRadius: BorderRadius.circular(Radii.large),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: TextSize.small,
                fontWeight: FontWeight.w700,
                color: deepOf(color),
              ),
            ),
            PasswordField(controller: controller, hint: '', plain: true),
          ],
        ),
      ),
    );
    final first = widget.first;
    return CenterPanel(
      glyph: Glyph.key,
      color: color,
      title: first ? '設定密碼' : '變更密碼',
      detail: '至少 6 個字',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!first) field(_current, '目前的密碼'),
          field(_next, '新密碼'),
          field(_again, '再輸入一次'),
          if (_problem case final problem?)
            Text(problem, style: const TextStyle(color: Hue.danger)),
        ],
      ),
      actions: [
        PanelButton(Words.cancel, onTap: () => Navigator.of(context).pop()),
        PanelButton(
          first ? '設定' : '變更',
          key: Keys.changePassword,
          color: color,
          onTap: _submit,
        ),
      ],
    );
  }
}
