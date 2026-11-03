import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../backup/model/drive_backup.dart';
import '../../../backup/model/drive_sync.dart';
import '../../../backup/model/keeper.dart';
import '../../../backup/model/phone_backup.dart';
import '../../../../core/look/dialogs.dart';
import '../../../../core/look/glyphs.dart';
import '../../../../core/look/theme.dart';
import '../../../../core/look/widgets.dart';
import '../../../../core/problems.dart';
import '../../../lock/ui/recovery_code.dart';

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

/// 備份與還原: at the top, when the ledger was last backed up and where it
/// goes, on 總覽's tint, with a ring of two parts that light up for the
/// ways that are on; under it two rows that open in place. Google 備份 is
/// always on (Android takes the ledger to the person's Google account
/// each day) and holds the switch for the photos on Google Drive and
/// restoring from there; 檔案備份 holds saving to a folder on the phone,
/// a file to keep now, and restoring from a file. In each, the settings
/// come first and restoring is a button of its own below them.
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

enum _Open { none, google, files }

class _BackupSectionState extends State<BackupSection> {
  var _open = _Open.none;

  void _toggle(_Open part) =>
      setState(() => _open = _open == part ? _Open.none : part);

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

  /// Signs in with Google and sends the first backup with the photos.
  Future<void> _linkDrive(Keeper keeper, DriveSync drive) async {
    String? code;
    String note;
    try {
      code = await _codeFor(keeper);
      note = await drive.link()
          ? '已把帳本連同照片備份到 Google 雲端硬碟，之後每週一次'
          : '沒有連結 Google 雲端硬碟';
    } on DriveException catch (error) {
      note = error.message;
    } on Object catch (error) {
      note = '備份失敗：${describeProblem(error)}';
    }
    // The code changed even when the backup did not go up: shown anyway.
    if (code != null && mounted) {
      await showRecoveryCode(
        context,
        code,
        why: '在新手機還原雲端硬碟上的備份時，要輸入這組救援碼。請抄下來放在安全的地方，它只會顯示這一次。',
      );
    }
    if (mounted) showNote(context, note);
  }

  Future<void> _unlinkDrive(DriveSync drive) async {
    final ok = await confirm(
      context,
      '不再把照片備份到 Google 雲端硬碟？已經在雲端的備份會留著。',
      '停止',
    );
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

  @override
  Widget build(BuildContext context) {
    final drive = widget.drive;
    final phone = widget.phone;
    return ListenableBuilder(
      listenable: Listenable.merge([?drive, ?phone]),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _status(drive, phone),
          const SizedBox(height: 16),
          SoftPanel(
            color: Hue.white,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _google(drive),
                const Divider(height: 1, indent: 70, endIndent: 16),
                _files(phone),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 14, 12, 0),
            child: Text(
              '帳本每天自動備份到你的 Google 帳戶，重裝或換手機時可以拿回來。',
              style: TextStyle(fontSize: 12.5, height: 1.6, color: Hue.muted),
            ),
          ),
        ],
      ),
    );
  }

  /// When the ledger was last backed up, and a line for each way.
  Widget _status(DriveSync? drive, PhoneBackup? phone) {
    final photos = drive?.linked ?? false;
    final folder = phone?.on ?? false;
    final daily = phone?.daily ?? true;
    final latest = _latest([
      widget.keeper.cloudCopyAt,
      if (photos) drive?.backedUp,
      if (folder) phone?.backedUp,
    ]);
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Hue.tile, Hue.hero],
          ),
        ),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 84,
              child: CustomPaint(
                painter: _Ring(google: true, files: folder, dark: Shade.dark),
                child: const Center(
                  child: GlyphIcon(Glyph.safe, size: 28, color: Hue.accent),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '上次備份',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Hue.accent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    latest == null ? '還沒有備份' : _when(latest),
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _key(
                    on: true,
                    color: Hue.accent,
                    words: photos ? 'Google 每天，照片每週' : 'Google 每天',
                  ),
                  const SizedBox(height: 4),
                  _key(
                    on: folder,
                    color: Hue.cash,
                    words: folder
                        ? '檔案 ${daily ? '每天' : '每週'}存到資料夾'
                        : '檔案 沒有自動存',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _key({
    required bool on,
    required Color color,
    required String words,
  }) => Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? color : null,
          border: on ? null : Border.all(color: Hue.faint, width: 1.5),
        ),
      ),
      const SizedBox(width: 7),
      Flexible(
        child: Text(
          words,
          style: TextStyle(fontSize: 12.5, color: on ? Hue.ink : Hue.muted),
        ),
      ),
    ],
  );

  Widget _google(DriveSync? drive) {
    final at = widget.keeper.cloudCopyAt;
    return _Group(
      glyph: Glyph.download,
      title: 'Google 備份',
      detail: at == null ? '每天自動' : '每天自動 · 上次 ${_when(at)}',
      open: _open == _Open.google,
      onTap: () => _toggle(_Open.google),
      children: [
        if (drive != null)
          _Setting(
            title: '連同收據照片',
            detail: drive.busy
                ? '備份中…'
                : drive.linked && drive.backedUp != null
                ? '存到雲端硬碟 · 上次 ${_when(drive.backedUp!)}'
                : '照片存到雲端硬碟，每週一次',
            trailing: Switch(
              value: drive.linked,
              onChanged: drive.busy
                  ? null
                  : (on) => on
                        ? _linkDrive(widget.keeper, drive)
                        : _unlinkDrive(drive),
            ),
          ),
        _Restore(
          glyph: Glyph.reset,
          label: '從雲端硬碟還原',
          onTap: () => restoreFromBackup(context, widget.keeper),
        ),
      ],
    );
  }

  Widget _files(PhoneBackup? phone) {
    final on = phone?.on ?? false;
    final daily = phone?.daily ?? true;
    final at = phone?.backedUp;
    return _Group(
      glyph: Glyph.records,
      title: '檔案備份',
      detail: on
          ? '${daily ? '每天' : '每週'}存到資料夾'
                '${at == null ? '' : ' · 上次 ${_when(at)}'}'
          : '匯出一份，或從檔案還原',
      open: _open == _Open.files,
      onTap: () => _toggle(_Open.files),
      children: [
        if (phone != null) ...[
          _Setting(
            title: '自動存到資料夾',
            detail: phone.busy
                ? '備份中…'
                : phone.problem != null
                ? '上次沒有成功，關掉再打開可以重選資料夾'
                : '含照片 · 只留最新 5 份',
            trailing: Switch(
              value: on,
              onChanged: phone.busy
                  ? null
                  : (next) => next ? _choosePhone(phone) : _stopPhone(phone),
            ),
          ),
          if (on) ...[
            _Setting(
              title: '多久一次',
              detail: '有變更才備份',
              value: phone.daily ? '每天' : '每週',
              onTap: () => phone.setDaily(!phone.daily),
            ),
            _Setting(
              title: '資料夾',
              value: phone.folderName,
              onTap: phone.busy ? null : () => _choosePhone(phone),
            ),
          ],
        ],
        Row(
          children: [
            Expanded(
              child: _Restore(
                glyph: Glyph.download,
                label: '現在匯出一份',
                onTap: () => _export(widget.keeper),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Restore(
                glyph: Glyph.reset,
                label: '從檔案還原',
                onTap: () => restoreFromBackup(context, widget.keeper),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One way of backing up: a row with its state that opens in place onto
/// [children], on a tinted inset.
class _Group extends StatelessWidget {
  const _Group({
    required this.glyph,
    required this.title,
    required this.detail,
    required this.open,
    required this.onTap,
    required this.children,
  });

  final Glyph glyph;
  final String title;
  final String detail;
  final bool open;
  final VoidCallback onTap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Semantics(
          expanded: open,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 68),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Hue.tile,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: GlyphIcon(glyph, size: 20, color: Hue.accent),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontSize: 16)),
                          const SizedBox(height: 2),
                          Text(
                            detail,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Hue.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: GlyphIcon(
                        Glyph.next,
                        size: 18,
                        color: open ? Hue.accent : Hue.faint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: open
              ? Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                  decoration: BoxDecoration(
                    color: Hue.paper,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, child) in children.indexed) ...[
                        if (i > 0 && child is _Setting)
                          const Divider(height: 1),
                        if (child is! _Setting) const SizedBox(height: 10),
                        child,
                      ],
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// A setting inside a [_Group]: its name and a line under it, and a
/// switch, or a value that a tap changes.
class _Setting extends StatelessWidget {
  const _Setting({
    required this.title,
    this.detail,
    this.trailing,
    this.value,
    this.onTap,
  });

  final String title;
  final String? detail;
  final Widget? trailing;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;
    final value = this.value;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 14.5)),
                    if (detail != null)
                      Text(
                        detail,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Hue.muted,
                        ),
                      ),
                  ],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Hue.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                const GlyphIcon(Glyph.next, size: 16, color: Hue.accent),
              ],
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// An action below a [_Group]'s settings, such as restoring: a white
/// pill, so it is not taken for a setting.
class _Restore extends StatelessWidget {
  const _Restore({
    required this.glyph,
    required this.label,
    required this.onTap,
  });

  final Glyph glyph;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: Hue.white,
        foregroundColor: Hue.accent,
        side: const BorderSide(color: Hue.accentRule, width: 1.5),
        shape: const StadiumBorder(),
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlyphIcon(glyph, size: 17, color: Hue.accent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// The ring of the status tile: one half for Google, one for files, each
/// coloured when that way is on.
class _Ring extends CustomPainter {
  const _Ring({required this.google, required this.files, required this.dark});

  final bool google;
  final bool files;

  /// Painted again when the theme changes.
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    // A gap between the halves, at the top and the bottom.
    const gap = 0.32;
    for (final (i, on, color) in [
      (0, google, Hue.accent),
      (1, files, Hue.cash),
    ]) {
      canvas.drawArc(
        rect,
        -math.pi / 2 + i * math.pi + gap / 2,
        math.pi - gap,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = on ? color : Hue.line,
      );
    }
  }

  @override
  bool shouldRepaint(_Ring old) =>
      old.google != google || old.files != files || old.dark != dark;
}
