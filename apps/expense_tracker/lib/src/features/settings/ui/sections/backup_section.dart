import 'package:flutter/material.dart';

import '../../../backup/model/drive_backup.dart';
import '../../../backup/model/drive_sync.dart';
import '../../../backup/model/keeper.dart';
import '../../../backup/model/phone_backup.dart';
import '../../../../core/look/dialogs.dart';
import '../../../../core/look/glyphs.dart';
import '../../../../core/look/widgets.dart';
import '../../../../core/problems.dart';
import '../../../lock/ui/recovery_code.dart';

/// 備份與還原: a backup file to keep outside the app, weekly backups on
/// Google Drive, and restoring a backup in place of this ledger.
class BackupSection extends StatefulWidget {
  const BackupSection({
    super.key,
    required this.keeper,
    this.drive,
    this.phone,
  });

  final Keeper keeper;

  /// Backups on Google Drive, on Android.
  final DriveSync? drive;

  /// Backups to a folder on the phone, on Android.
  final PhoneBackup? phone;

  @override
  State<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<BackupSection> {
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
    final ok = await confirm(context, '停止備份到 Google 雲端硬碟？已經在雲端的備份會留著。', '停止');
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

  /// Chooses the folder and writes the first backup into it.
  Future<void> _choosePhone(PhoneBackup phone) async {
    String? note;
    try {
      if (await phone.choose()) {
        note = '已備份到「${phone.folderName}」，之後${phone.daily ? '每天' : '每週'}自動備份';
      }
    } on Object catch (error) {
      note = '沒有備份到手機資料夾：${describeProblem(error)}';
    }
    if (mounted && note != null) showNote(context, note);
  }

  Future<void> _phoneNow(PhoneBackup phone) async {
    String note;
    try {
      await phone.backUpNow();
      note = '已備份到「${phone.folderName}」';
    } on Object catch (error) {
      note = '沒有備份到手機資料夾：${describeProblem(error)}';
    }
    if (mounted) showNote(context, note);
  }

  Future<void> _stopPhone(PhoneBackup phone) async {
    final ok = await confirm(context, '停止自動備份到手機？資料夾裡的備份會留著。', '停止');
    if (!ok) return;
    await phone.stop();
    if (mounted) showNote(context, '已停止備份到手機資料夾');
  }

  static String _last(DateTime? at) {
    if (at == null) return '還沒有備份';
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '上次 ${local.month}/${local.day} ${two(local.hour)}:${two(local.minute)}';
  }

  Widget _phoneRows(PhoneBackup phone) => ListenableBuilder(
    listenable: phone,
    builder: (context, _) {
      if (!phone.on) {
        return MenuRow(
          glyph: Glyph.phone,
          title: '自動備份到手機',
          detail: phone.busy ? '備份中…' : '選一個資料夾，含照片，保留 5 份',
          onTap: phone.busy ? null : () => _choosePhone(phone),
        );
      }
      return Column(
        children: [
          MenuRow(
            glyph: Glyph.phone,
            title: '手機資料夾備份',
            detail: phone.busy
                ? '備份中…'
                : phone.problem != null
                ? '上次沒有成功，點一下重試'
                : '「${phone.folderName}」· ${_last(phone.backedUp)}',
            onTap: phone.busy ? null : () => _phoneNow(phone),
            trailing: TextButton(
              onPressed: phone.busy ? null : () => _stopPhone(phone),
              child: const Text('停止'),
            ),
          ),
          MenuRow(
            glyph: Glyph.calendar,
            title: '自動備份頻率',
            detail: phone.daily ? '每天（有變更才備份）' : '每週（有變更才備份）',
            trailing: Switch(
              value: phone.daily,
              onChanged: phone.setDaily,
            ),
          ),
        ],
      );
    },
  );

  /// Keeps a backup of this ledger, then opens the lock screen on
  /// choosing the backup to restore, from the phone or Google Drive.
  Future<void> _restore(Keeper keeper) async {
    final ok = await confirm(
      context,
      '從備份還原？會先把目前的帳本連同照片備份一份，再換成你選的備份。',
      '選擇備份',
    );
    if (!ok) return;
    try {
      await keeper.restoreAnother();
    } on Object catch (error) {
      if (mounted) showNote(context, '沒有開始還原：${describeProblem(error)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final keeper = widget.keeper;
    return MenuPanel([
      MenuRow(
        glyph: Glyph.safe,
        title: '備份帳本',
        detail: '含收據照片 · 存成檔案',
        onTap: () => _export(keeper),
      ),
      if (widget.phone case final phone?) _phoneRows(phone),
      if (widget.drive case final drive?) _driveRow(keeper, drive),
      MenuRow(
        glyph: Glyph.reset,
        title: '從備份還原',
        detail: '手機裡的檔案或雲端硬碟',
        onTap: () => _restore(keeper),
      ),
    ]);
  }
}
