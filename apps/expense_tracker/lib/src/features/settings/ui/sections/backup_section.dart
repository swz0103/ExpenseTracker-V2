import 'package:flutter/material.dart';

import '../../../backup/model/drive_backup.dart';
import '../../../backup/model/drive_sync.dart';
import '../../../backup/model/keeper.dart';
import '../../../backup/model/phone_backup.dart';
import '../../../../core/look/dialogs.dart';
import '../../../../core/look/glyphs.dart';
import '../../../../core/look/theme.dart';
import '../../../../core/look/widgets.dart';
import '../../../../core/preferences.dart';
import '../../../../core/problems.dart';
import '../../../lock/ui/recovery_code.dart';
import '../settings_hue.dart';

/// Keeps a backup of this ledger, then opens the lock screen on choosing
/// the backup to restore, from a file or Google Drive.
Future<void> restoreFromBackup(BuildContext context, Keeper keeper) async {
  final ok = await confirm(context, '從備份還原？會先把目前的帳本連同照片備份一份，再換成你選的備份。', '選擇備份');
  if (!ok) return;
  try {
    await keeper.restoreAnother();
  } on Object catch (error) {
    if (context.mounted) {
      showNote(context, '沒有開始還原：${describeProblem(error)}');
    }
  }
}

/// 備份與還原: the main card says only when the ledger was last backed up
/// (gold when neither the Drive nor a folder is on); then two tinted
/// cards, each with its tick: Google 雲端硬碟 (linked, when it last went
/// up and whether the receipt photos go too) and 存到資料夾 (on, how often
/// and which folder); and 手動: 匯出一份 and 還原.
class BackupSection extends StatefulWidget {
  const BackupSection({
    super.key,
    required this.keeper,
    this.drive,
    this.phone,
    this.preferences,
  });

  final Keeper keeper;

  /// Redraws the page when a setting changes.
  final Preferences? preferences;

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
      final code = await _codeFor(keeper);
      final saved = await keeper.exportBackup();
      if (!mounted) return;
      if (code != null) {
        // The code changed even if the save was cancelled: show it anyway.
        await showRecoveryCode(
          context,
          code,
          why: saved ? '在新手機還原這份備份時要輸入它' : '之前的救援碼不再適用',
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

  /// Signs in with Google and sends the first backup of the ledger.
  Future<void> _linkDrive(Keeper keeper, DriveSync drive) async {
    String? code;
    String note;
    try {
      code = await _codeFor(keeper);
      note = await drive.link()
          ? '已把帳本備份到 Google 雲端硬碟，之後有變動就每天一次'
          : '沒有連結 Google 雲端硬碟';
    } on DriveException catch (error) {
      note = error.message;
    } on Object catch (error) {
      note = '備份失敗：${describeProblem(error)}';
    }
    // The code changed even when the backup did not go up: shown anyway.
    if (code != null && mounted) {
      await showRecoveryCode(context, code, why: '在新手機還原雲端硬碟上的備份時要輸入它');
    }
    if (mounted) showNote(context, note);
  }

  /// Adds the receipt photos to the backups on Drive, sending one with
  /// them now, or leaves them out from the next.
  Future<void> _drivePhotos(DriveSync drive, bool on) async {
    try {
      await drive.setPhotos(on);
      if (mounted && on) showNote(context, '已連同收據照片備份到雲端硬碟');
    } on DriveException catch (error) {
      if (mounted) showNote(context, error.message);
    } on Object catch (error) {
      if (mounted) showNote(context, '備份失敗：${describeProblem(error)}');
    }
  }

  Future<void> _unlinkDrive(DriveSync drive) async {
    final ok = await confirm(context, '不再備份到 Google 雲端硬碟？已經在雲端的備份會留著。', '停止');
    if (!ok) return;
    await drive.unlink();
    if (mounted) showNote(context, '已停止雲端硬碟備份');
  }

  /// Says which folders Android lets the app keep, then opens the
  /// chooser at Documents and writes the first backup into the folder
  /// picked. A place Android will not keep is said plainly and the
  /// chooser opens again.
  Future<void> _choosePhone(PhoneBackup phone) async {
    var go = await _folderRules(
      '選一個已經有的資料夾，例如「文件（Documents）」或裡面的資料夾。'
          'Android 不讓 App 直接用「下載」或儲存空間最外層。備份檔會直接放在你選的資料夾裡。',
      '選資料夾',
    );
    while (go && mounted) {
      String? note;
      try {
        if (await phone.choose()) {
          note = '已備份到「${phone.folderName}」，之後${phone.daily ? '每天' : '每週'}自動備份';
        }
        go = false;
      } on FolderRejected {
        go = await _folderRules(
          'Android 不讓 App 存到這個位置（「下載」或儲存空間最外層都不行）。'
              '請進到「文件（Documents）」或其他資料夾裡，再按「使用這個資料夾」。',
          '重新選',
        );
      } on Object catch (error) {
        note = '沒有備份到手機資料夾：${describeProblem(error)}';
        go = false;
      }
      if (mounted && note != null) showNote(context, note);
    }
  }

  /// The panel before the folder chooser: [rules], 取消 and [action].
  Future<bool> _folderRules(String rules, String action) async {
    final go = await showPanel<bool>(
      context,
      (context) => CenterPanel(
        glyph: Glyph.records,
        color: SettingsHue.folder,
        title: '存到資料夾',
        body: Text(rules, style: const TextStyle(fontSize: 15, height: 1.5)),
        actions: [
          PanelButton('取消', onTap: () => Navigator.of(context).pop(false)),
          PanelButton(
            action,
            color: SettingsHue.folder,
            onTap: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    return go ?? false;
  }

  Future<void> _stopPhone(PhoneBackup phone) async {
    final ok = await confirm(context, '停止自動備份到手機？資料夾裡的備份會留著。', '停止');
    if (!ok) return;
    await phone.stop();
    if (mounted) showNote(context, '已停止備份到手機資料夾');
  }

  /// 今天 21:03, 昨天 08:14, or 11/2 08:14.
  static String _when(DateTime at) {
    final local = at.toLocal();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final time = '${two(local.hour)}:${two(local.minute)}';
    final day = DateTime(local.year, local.month, local.day);
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(day).inDays;
    if (days == 0) return '今天 $time';
    if (days == 1) return '昨天 $time';
    return '${local.month}/${local.day} $time';
  }

  static DateTime? _latest(Iterable<DateTime?> times) {
    DateTime? latest;
    for (final at in times) {
      if (at != null && (latest == null || at.isAfter(latest))) latest = at;
    }
    return latest;
  }

  @override
  Widget build(BuildContext context) {
    final drive = widget.drive;
    final phone = widget.phone;
    final preferences = widget.preferences;
    return ListenableBuilder(
      listenable: Listenable.merge([?drive, ?phone, ?preferences]),
      builder: (context, _) {
        final folder = phone?.on ?? false;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _status(folder: folder),
            if (drive != null) ...[
              const SizedBox(height: 12),
              _driveCard(drive),
            ],
            if (phone != null) ...[
              const SizedBox(height: 12),
              _folderCard(phone),
            ],
            const RuleHead('手動'),
            Row(
              children: [
                Expanded(
                  child: _Manual(
                    glyph: Glyph.upload,
                    label: '匯出一份',
                    color: SettingsHue.csv,
                    onTap: () => _export(widget.keeper),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Manual(
                    glyph: Glyph.download,
                    label: '還原',
                    color: SettingsHue.invoice,
                    onTap: () => restoreFromBackup(context, widget.keeper),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// The latest backup to the Drive or the folder, whichever is on.
  /// Android's own backup of the ledger, for a new phone, goes on as it
  /// did but is not shown: no one can see it or make it happen.
  Widget _status({required bool folder}) {
    final drive = widget.drive;
    final phone = widget.phone;
    final linked = drive?.linked ?? false;
    final latest = _latest([
      if (linked) drive?.backedUp,
      if (folder) phone?.backedUp,
    ]);
    return BackupHero(
      at: latest,
      on: linked || folder,
      label: linked || folder ? null : '沒有自動備份',
    );
  }

  /// Google Drive: its tick links or unlinks it; linked, when it last
  /// went up and whether the receipt photos go too.
  Widget _driveCard(DriveSync drive) {
    const color = SettingsHue.backup;
    final linked = drive.linked;
    return _BackupCard(
      glyph: Glyph.upload,
      color: color,
      title: 'Google 雲端硬碟',
      value: linked,
      onChanged: drive.busy
          ? null
          : (v) => v ? _linkDrive(widget.keeper, drive) : _unlinkDrive(drive),
      rows: [
        if (linked) ...[
          _CardRow(
            color: color,
            title: '上次備份',
            value: drive.busy
                ? '備份中…'
                : switch (drive.backedUp) {
                    final at? => _when(at),
                    null => '還沒有',
                  },
          ),
          _CardRow(
            color: color,
            title: '收據照片',
            detail: drive.photos ? '連 Wi-Fi 時一起備份' : null,
            trailing: TickSwitch(
              value: drive.photos,
              color: color,
              label: '收據照片',
              onChanged: drive.busy ? null : (v) => _drivePhotos(drive, v),
            ),
            onTap: drive.busy ? null : () => _drivePhotos(drive, !drive.photos),
          ),
        ],
      ],
    );
  }

  Widget _folderCard(PhoneBackup phone) {
    const color = SettingsHue.folder;
    final on = phone.on;
    return _BackupCard(
      glyph: Glyph.records,
      color: color,
      title: '存到資料夾',
      value: on,
      onChanged: phone.busy
          ? null
          : (next) => next ? _choosePhone(phone) : _stopPhone(phone),
      rows: [
        if (on) ...[
          _CardRow(
            color: color,
            title: '多久一次',
            detail: phone.problem != null ? '上次沒有成功' : null,
            value: phone.daily ? '每天' : '每週',
            onTap: () => phone.setDaily(!phone.daily),
          ),
          _CardRow(
            color: color,
            title: '資料夾',
            value: phone.folderName,
            onTap: phone.busy ? null : () => _choosePhone(phone),
          ),
        ],
      ],
    );
  }
}

/// 上次備份 and when, on a card in the interface colour; gold with
/// [label] when no automatic backup is on.
class BackupHero extends StatelessWidget {
  const BackupHero({
    super.key,
    required this.at,
    required this.on,
    this.label,
    this.trailing,
    this.onTap,
    this.stale = false,
  });

  final DateTime? at;

  /// Whether any automatic backup is on.
  final bool on;

  /// Said in place of the time, such as 沒有自動備份.
  final String? label;

  /// Under the time, such as the two ways that are on.
  final Widget? trailing;
  final VoidCallback? onTap;

  /// No backup for more than three days: gold.
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final warn = !on || stale;
    final color = warn ? SettingsHue.warning : SettingsHue.backup;
    final at = this.at;
    final days = at == null
        ? null
        : DateTime.now().difference(at.toLocal()).inDays;
    final small = !on
        ? (at == null ? '還沒有備份' : '上次 ${_BackupSectionState._when(at)}')
        : stale && days != null
        ? '上次 ${_BackupSectionState._when(at!)}'
        : '上次備份';
    final big =
        label ??
        (at == null
            ? '還沒有備份'
            : stale && days != null
            ? '已經 $days 天沒備份'
            : _BackupSectionState._when(at));
    return ColorCard(
      color: color,
      amount: 0.22,
      onTap: onTap,
      label: '$small，$big',
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SquareIcon(Glyph.safe, color, size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      small,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: deepOf(color),
                      ),
                    ),
                    Text(
                      big,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const GlyphIcon(Glyph.next, size: 18, color: Hue.muted),
            ],
          ),
          if (trailing != null) ...[const SizedBox(height: 12), trailing!],
        ],
      ),
    );
  }
}

/// A way of backing up as a tinted card: its icon, name and tick, then
/// its settings below thin rules, each with its value on the right.
class _BackupCard extends StatelessWidget {
  const _BackupCard({
    required this.glyph,
    required this.color,
    required this.title,
    required this.value,
    required this.onChanged,
    required this.rows,
  });

  final Glyph glyph;
  final Color color;
  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final change = onChanged;
    return ColorCard(
      color: color,
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      child: Column(
        children: [
          ToggleRow(
            value: value,
            onChanged: change,
            label: title,
            child: Row(
              children: [
                SquareIcon(glyph, color, size: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: deepOf(color),
                    ),
                  ),
                ),
                TickSwitch(
                  value: value,
                  color: color,
                  label: title,
                  onChanged: change,
                ),
              ],
            ),
          ),
          for (final row in rows) ...[
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Divider(height: 12, color: tintOf(color, 0.4)),
            ),
            row,
          ],
        ],
      ),
    );
  }
}

/// A setting on a [_BackupCard]: its name, and on the right its value
/// with › or a control.
class _CardRow extends StatelessWidget {
  const _CardRow({
    required this.color,
    required this.title,
    this.detail,
    this.value,
    this.trailing,
    this.onTap,
  });

  final Color color;
  final String title;
  final String? detail;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = deepOf(color);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  if (detail != null)
                    Text(detail!, style: TextStyle(fontSize: 12.5, color: ink)),
                ],
              ),
            ),
            if (value != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  '${value!} ›',
                  style: TextStyle(fontWeight: FontWeight.w700, color: ink),
                ),
              ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// 匯出一份 or 還原: a tinted button with an icon.
class _Manual extends StatelessWidget {
  const _Manual({
    required this.glyph,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final Glyph glyph;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = deepOf(color);
    return ColorCard(
      color: color,
      radius: 18,
      amount: 0.18,
      label: label,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GlyphIcon(glyph, size: 20, color: ink, tinted: false),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}
