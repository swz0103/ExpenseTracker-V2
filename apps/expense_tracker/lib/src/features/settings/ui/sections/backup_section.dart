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
/// (gold when no automatic backup is on); then two tinted cards, each
/// with its tick: Google 備份 (Android takes the encrypted ledger to the
/// person's Google account each day; on, the receipt photos can go to
/// Google Drive as well) and 存到資料夾 (on, how often and which folder);
/// and 手動: 匯出一份 and 還原.
class BackupSection extends StatefulWidget {
  const BackupSection({
    super.key,
    required this.keeper,
    this.drive,
    this.phone,
    this.preferences,
  });

  final Keeper keeper;

  /// Holds whether Google 備份 is on; without it, it is always on.
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

  /// Turns Google 備份 on, writing the copy now, or off, deleting it and
  /// stopping the photos on Drive.
  Future<void> _google(bool on, Preferences preferences) async {
    final drive = widget.drive;
    if (!on) {
      final ok = await confirm(
        context,
        '關掉 Google 備份？換手機或重裝時就拿不回帳本'
            '${drive?.linked ?? false ? '，雲端硬碟也不再備份' : ''}。',
        '關掉',
        danger: true,
      );
      if (!ok) return;
      preferences.update(googleBackup: false);
      try {
        await widget.keeper.dropCloudCopy();
        if (drive != null && drive.linked) await drive.unlink();
      } on Object catch (error) {
        if (mounted) showNote(context, describeProblem(error));
      }
      if (mounted) setState(() {});
      return;
    }
    preferences.update(googleBackup: true);
    if (mounted) showNote(context, '離開 App 時會更新 Google 備份');
  }

  @override
  Widget build(BuildContext context) {
    final drive = widget.drive;
    final phone = widget.phone;
    final preferences = widget.preferences;
    return ListenableBuilder(
      listenable: Listenable.merge([?drive, ?phone, ?preferences]),
      builder: (context, _) {
        final google = preferences?.googleBackup ?? true;
        final folder = phone?.on ?? false;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _status(google: google, folder: folder),
            const SizedBox(height: 12),
            _googleCard(google, drive, preferences),
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

  Widget _status({required bool google, required bool folder}) {
    final drive = widget.drive;
    final phone = widget.phone;
    final latest = _latest([
      if (google) widget.keeper.googleTakenAt,
      if (google && (drive?.linked ?? false)) drive?.backedUp,
      if (folder) phone?.backedUp,
    ]);
    return BackupHero(
      at: latest,
      on: google || folder,
      label: google || folder ? null : '沒有自動備份',
    );
  }

  /// When and where Android's own backup goes: the person cannot see it
  /// as a file, nor make it happen.
  void _explainGoogle() {
    final taken = widget.keeper.googleTakenAt;
    showCenterPanel(
      context,
      glyph: Glyph.safe,
      color: SettingsHue.backup,
      title: 'Google 備份',
      detail: [
        taken == null
            ? 'Android 還沒把帳本送到 Google。'
            : 'Android 上次送出：${_when(taken)}。',
        '手機大約一天一次，在充電、連著 Wi-Fi 又沒在用時送出，App 沒辦法要它馬上送。',
        '要先在手機的「設定 › Google › 備份」打開備份。',
        '它存在 Google 帳戶的備份裡（Google 雲端硬碟 › 備份），不是一般檔案；換手機或重裝時，歡迎頁會問要不要還原。',
        '想在雲端硬碟看到檔案，打開下面的「雲端硬碟」：帳本有變動就每天存一份到「記帳本備份」資料夾，收據照片可另外選要不要一起帶。',
      ].join('\n\n'),
    );
  }

  Widget _googleCard(bool on, DriveSync? drive, Preferences? preferences) {
    const color = SettingsHue.backup;
    return _BackupCard(
      glyph: Glyph.safe,
      color: color,
      title: 'Google 備份',
      value: on,
      onChanged: preferences == null ? null : (v) => _google(v, preferences),
      rows: [
        if (on)
          _CardRow(
            color: color,
            title: '帳本',
            value: switch (widget.keeper.googleTakenAt) {
              final at? => _when(at),
              null => '還沒送出',
            },
            onTap: _explainGoogle,
          ),
        if (on && drive != null) ...[
          _CardRow(
            color: color,
            title: '雲端硬碟',
            detail: drive.busy
                ? '備份中…'
                : drive.linked && drive.backedUp != null
                ? '上次 ${_when(drive.backedUp!)}'
                : null,
            trailing: TickSwitch(
              value: drive.linked,
              color: color,
              label: '雲端硬碟',
              onChanged: drive.busy
                  ? null
                  : (v) => v
                        ? _linkDrive(widget.keeper, drive)
                        : _unlinkDrive(drive),
            ),
          ),
          if (drive.linked)
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
          Row(
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
