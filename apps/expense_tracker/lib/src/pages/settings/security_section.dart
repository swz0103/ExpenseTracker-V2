import 'package:flutter/material.dart';

import '../../book/drive_backup.dart';
import '../../book/drive_sync.dart';
import '../../book/keeper.dart';
import '../../look/dialogs.dart';
import '../../look/glyphs.dart';
import '../../look/theme.dart';
import '../../look/widgets.dart';
import '../../problems.dart';
import '../../screen_privacy.dart';
import '../recovery_code.dart';

/// 安全: backing up the encrypted ledger, its password and recovery code,
/// hiding the screens, and locking the ledger again.
class SecuritySection extends StatefulWidget {
  const SecuritySection({super.key, this.keeper, this.privacy, this.drive});

  final Keeper? keeper;
  final ScreenPrivacy? privacy;

  /// Backups on Google Drive, on Android.
  final DriveSync? drive;

  @override
  State<SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<SecuritySection> {
  /// Saves a backup outside the app. Without a password, only a recovery
  /// code opens it on another phone, so a new one is made and shown.
  Future<void> _export(Keeper keeper) async {
    try {
      // A ledger without a password restores with its recovery code: one
      // is made the first time, and kept after that.
      final code = keeper.hasPassword || keeper.recoveryGiven
          ? null
          : await keeper.newRecoveryCode();
      final saved = await keeper.exportBackup();
      if (!mounted) return;
      if (code != null) {
        // The code changed even if the save was cancelled: show it anyway.
        await showRecoveryCode(
          context,
          code,
          why: saved
              ? '在新手機還原這份備份時，要輸入這組救援碼。請抄下來放在安全的地方，它只會顯示這一次。'
              : '救援碼已更新，之前的不再適用。請抄下來放在安全的地方，它只會顯示這一次。',
        );
      } else if (saved) {
        showNote(
          context,
          keeper.hasPassword ? '已匯出備份檔' : '已匯出備份檔，還原時輸入你抄下的救援碼',
        );
      }
    } on Object catch (error) {
      if (mounted) showNote(context, '匯出失敗：${describeProblem(error)}');
    }
  }

  /// A ledger without a password restores with its recovery code: one is
  /// made the first time a backup leaves the phone, and shown.
  Future<String?> _codeFor(Keeper keeper) async =>
      keeper.hasPassword || keeper.recoveryGiven
      ? null
      : await keeper.newRecoveryCode();

  Future<void> _showCode(String? code) async {
    if (code == null || !mounted) return;
    await showRecoveryCode(
      context,
      code,
      why: '在新手機還原雲端硬碟上的備份時，要輸入這組救援碼。請抄下來放在安全的地方，它只會顯示這一次。',
    );
  }

  /// Signs in with Google and sends the first backup.
  Future<void> _linkDrive(Keeper keeper, DriveSync drive) async {
    String? code;
    String note;
    try {
      code = await _codeFor(keeper);
      note = await drive.link()
          ? '已備份到 Google 雲端硬碟，之後每週自動備份'
          : '沒有連結 Google 雲端硬碟';
    } on DriveException catch (error) {
      note = error.message;
    } on Object catch (error) {
      note = '備份失敗：${describeProblem(error)}';
    }
    // The code changed even when the backup did not go up: shown anyway.
    await _showCode(code);
    if (mounted) showNote(context, note);
  }

  Future<void> _driveNow(Keeper keeper, DriveSync drive) async {
    String? code;
    String note;
    try {
      code = await _codeFor(keeper);
      await drive.backUpNow();
      note = '已備份到 Google 雲端硬碟';
    } on DriveException catch (error) {
      note = error.message;
    } on Object catch (error) {
      note = '備份失敗：${describeProblem(error)}';
    }
    await _showCode(code);
    if (mounted) showNote(context, note);
  }

  Future<void> _unlinkDrive(DriveSync drive) async {
    final ok = await confirm(
      context,
      '停止備份到 Google 雲端硬碟？已經在雲端的備份會留著。',
      '停止',
    );
    if (!ok) return;
    await drive.unlink();
    if (mounted) showNote(context, '已停止雲端硬碟備份');
  }

  static String _when(DateTime? at) {
    if (at == null) return '還沒有備份';
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '上次 ${local.month}/${local.day} ${two(local.hour)}:${two(local.minute)}'
        ' · 每週自動';
  }

  Widget _driveRow(Keeper keeper, DriveSync drive) => ListenableBuilder(
    listenable: drive,
    builder: (context, _) => drive.linked
        ? MenuRow(
            glyph: Glyph.download,
            title: 'Google 雲端硬碟備份',
            detail: drive.busy ? '備份中…' : _when(drive.backedUp),
            onTap: drive.busy ? null : () => _driveNow(keeper, drive),
            trailing: TextButton(
              onPressed: drive.busy ? null : () => _unlinkDrive(drive),
              child: const Text('停止'),
            ),
          )
        : MenuRow(
            glyph: Glyph.download,
            title: '備份到 Google 雲端硬碟',
            detail: drive.busy ? '備份中…' : '登入 Google，每週自動備份',
            onTap: drive.busy ? null : () => _linkDrive(keeper, drive),
          ),
  );

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
        const SectionHead('安全'),
        MenuPanel([
          if (keeper != null) ...[
            MenuRow(
              glyph: Glyph.safe,
              title: '備份帳本',
              detail: '含收據照片 · 存成檔案',
              onTap: () => _export(keeper),
            ),
            if (widget.drive case final drive?) _driveRow(keeper, drive),
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
