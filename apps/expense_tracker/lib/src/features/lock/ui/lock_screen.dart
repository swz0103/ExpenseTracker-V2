import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_backup.dart';

import '../../backup/model/drive_backup.dart';
import '../model/restore_sources.dart';
import '../model/startup.dart';
import 'views/lock_parts.dart';
import 'views/recovery_view.dart';
import 'views/restore_view.dart';
import 'views/unlock_view.dart';
import 'views/welcome_view.dart';

/// The first screen of the phone app. A new ledger starts with one tap,
/// without a password (one can be set later in settings), or from a
/// backup. A ledger with a password asks for it, a fingerprint or the
/// recovery code; one without opens by itself after the opening
/// animation.
class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.startup,
    this.sources = const RestoreSources(),
  });

  final Startup startup;

  /// The file picker and Google Drive, on a phone.
  final RestoreSources sources;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _password = TextEditingController();
  final _file = TextEditingController();
  var _recovery = false;

  /// Restoring a backup instead of creating an empty ledger.
  var _restoring = false;

  /// Back on the first screen from the backup form: the choices show at
  /// once, without the opening again.
  var _cameBack = false;
  var _busy = false;
  String? _problem;

  /// The copy of the backup chosen with the file picker or downloaded
  /// from Google Drive, in the cache.
  String? _picked;

  /// Google Drive, once a backup is looked for there.
  DriveBackup? _drive;

  /// The first screen of a new ledger, before any choice.
  bool get _welcome => widget.startup.state is NeedsSetup && !_restoring;

  /// A ledger without a password, opening by itself, unless a backup is
  /// being restored in its place.
  bool get _quiet =>
      widget.startup.state is Locked &&
      widget.startup.passwordless &&
      !_restoring;

  /// This phone can open the ledger with a fingerprint or face.
  bool get _biometric => switch (widget.startup.state) {
    Locked(:final deviceUnlock) => deviceUnlock,
    _ => false,
  };

  /// Whether to ask for the fingerprint as the screen opens.
  bool get _askFirst => switch (widget.startup.state) {
    Locked(:final askFirst) => askFirst,
    _ => false,
  };

  /// When the chosen backup was taken and what it holds.
  String? _about;

  @override
  void initState() {
    super.initState();
    // Asked for in settings: restore a backup in place of this ledger.
    _restoring = widget.startup.takeRestore();
    if (_restoring || _welcome) return;
    if (_quiet) {
      // Opened once the opening animation has played (see build).
      _busy = true;
      return;
    }
    if (_biometric && _askFirst) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_unlockWithDevice());
      });
    }
  }

  /// Asks for the fingerprint or face. The first time, before this phone's
  /// key is enrolled by a password unlock, it says so instead.
  Future<void> _unlockWithDevice() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await widget.startup.unlockWithDevice();
    } on KeyringException catch (error) {
      _fail(
        error.error == KeyringError.unknownDevice
            ? '先用密碼打開一次，之後就能用指紋解鎖'
            : '指紋解鎖失敗，請改用密碼',
      );
    } on Object {
      _fail('指紋解鎖已取消，可以改用密碼');
    }
  }

  Future<void> _openQuietly() async {
    try {
      await widget.startup.openQuietly();
    } on Object catch (error) {
      _fail('無法開啟帳本（$error）');
    }
  }

  /// Starts a new ledger without a password.
  Future<void> _start() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await widget.startup.setUpWithoutPassword();
    } on Object catch (error) {
      _fail('無法建立帳本（$error）');
    }
  }

  @override
  void dispose() {
    _password.dispose();
    _file.dispose();
    _forgetPicked();
    super.dispose();
  }

  /// Deletes the copy of the chosen backup once it is not needed: after
  /// it was restored, or when this screen goes. A failed restore keeps it
  /// for another try; the next start deletes one left behind.
  void _forgetPicked() {
    final picked = _picked;
    _picked = null;
    if (picked == null) return;
    try {
      final file = File(picked);
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // Deleted at the next start.
    }
  }

  Future<void> _submit() async {
    final secret = _password.text;
    setState(() {
      _busy = true;
      _problem = null;
    });
    final startup = widget.startup;
    try {
      if (_restoring) {
        await startup.restore(
          _file.text.trim(),
          _recovery ? secret.trim() : secret,
          recovery: _recovery,
        );
        _forgetPicked();
        return;
      }
      await (_recovery
          ? startup.unlockWithRecovery(secret.trim())
          : startup.unlockWithPassword(secret));
    } on BackupException catch (error) {
      _fail('無法讀取這個備份（${error.problem.name}）');
    } on FileSystemException {
      _fail('找不到這個備份檔');
    } on KeyringException catch (error) {
      _fail(switch (error.error) {
        KeyringError.wrongSecret => _recovery ? '救援碼不正確' : '密碼不正確',
        _ => '無法開啟帳本（${error.error.name}）',
      });
    } on Object catch (error) {
      _fail('無法開啟帳本（$error）');
    }
  }

  /// Opens the system's file chooser; the chosen backup is copied where
  /// the app can read it.
  Future<void> _pickBackup() async {
    final pick = widget.sources.pickFile;
    if (pick == null) return;
    final path = await pick();
    if (path == null || !mounted) return;
    if (path != _picked) _forgetPicked();
    _picked = path;
    setState(() => _file.text = path);
    await _describe(path);
  }

  /// Says when the backup at [path] was taken and how many records it
  /// holds, before its password is asked for.
  Future<void> _describe(String path) async {
    String about;
    try {
      final header = await widget.startup.peek(path);
      final at = header.createdAt.toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      about =
          '${at.year}/${at.month}/${at.day} ${two(at.hour)}:${two(at.minute)}'
          ' 的備份 · ${header.rows} 筆資料';
    } on Object {
      about = '這個檔案不是記帳本的備份';
    }
    if (mounted) setState(() => _about = about);
  }

  /// Lists the backups in 記帳本備份 on Google Drive, after Google's
  /// sign-in, and downloads the one chosen into the cache.
  Future<void> _pickDrive() async {
    final make = widget.sources.drive;
    final cache = widget.sources.cacheDirectory;
    if (make == null || cache == null) return;
    final drive = _drive ??= make();
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final files = await drive.list();
      if (!mounted) return;
      if (files.isEmpty) {
        _fail('Google 雲端硬碟的「${DriveBackup.folderName}」裡沒有備份');
        return;
      }
      setState(() => _busy = false);
      final chosen = await showModalBottomSheet<DriveFile>(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final file in files)
                ListTile(
                  title: Text(_driveLabel(file)),
                  subtitle: Text(file.name),
                  onTap: () => Navigator.of(context).pop(file),
                ),
            ],
          ),
        ),
      );
      if (chosen == null || !mounted) return;
      setState(() => _busy = true);
      _forgetPicked();
      final into = File('${(await cache()).path}/restore.etbk');
      await drive.download(chosen.id, into);
      _picked = into.path;
      if (!mounted) return;
      setState(() {
        _busy = false;
        _file.text = into.path;
      });
      await _describe(into.path);
    } on DriveException catch (error) {
      _fail(error.message);
    } on Object catch (error) {
      _fail('無法下載備份（$error）');
    }
  }

  /// Chooses the ledger as it was before an earlier restore from
  /// settings, kept on this phone: a way back from the wrong backup.
  Future<void> _pickKept() async {
    final kept = widget.startup.keptBeforeRestore();
    if (kept.isEmpty) return;
    final chosen = await showModalBottomSheet<File>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('還原前自動留下的帳本')),
            for (final file in kept)
              ListTile(
                title: Text(_fileLabel(file)),
                onTap: () => Navigator.of(context).pop(file),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    // Not a copy in the cache: kept as it is.
    _forgetPicked();
    setState(() => _file.text = chosen.path);
    await _describe(chosen.path);
  }

  static String _fileLabel(File file) {
    final at = file.lastModifiedSync();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${at.year}/${at.month}/${at.day} ${two(at.hour)}:${two(at.minute)} 留下';
  }

  static String _driveLabel(DriveFile file) {
    final at = file.modified.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final size = file.size == 0
        ? ''
        : ' · ${(file.size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${at.year}/${at.month}/${at.day} '
        '${two(at.hour)}:${two(at.minute)}$size';
  }

  void _fail(String problem) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = problem;
    });
  }

  /// Back from the backup form to the first screen; only a ledger not
  /// made yet has one.
  VoidCallback? get _back => widget.startup.state is NeedsSetup
      ? () => setState(() {
          _restoring = false;
          _recovery = false;
          _problem = null;
        })
      : _restoring
      ? _keepLedger
      : null;

  /// Restoring from settings given up: back to this ledger, which opens
  /// by itself when it has no password.
  void _keepLedger() {
    _forgetPicked();
    setState(() {
      _restoring = false;
      _recovery = false;
      _problem = null;
      _about = null;
      _file.clear();
      _password.clear();
    });
    // A ledger without a password opens after the opening animation.
    if (_quiet) setState(() => _busy = true);
  }

  /// Between the password and the recovery code.
  void _toggleRecovery() => setState(() {
    _recovery = !_recovery;
    _password.clear();
    _problem = null;
  });

  @override
  Widget build(BuildContext context) {
    if (_welcome) {
      return WelcomeView(
        busy: _busy,
        problem: _problem,
        animate: !_cameBack,
        onStart: _start,
        onRestore: () => setState(() {
          _restoring = true;
          _cameBack = true;
          _problem = null;
        }),
      );
    }
    if (_quiet && _problem == null) {
      return LockSplash(onDone: () => unawaited(_openQuietly()));
    }
    final Widget form;
    if (_restoring) {
      form = RestoreView(
        file: _file,
        secret: _password,
        recovery: _recovery,
        busy: _busy,
        problem: _problem,
        onSubmit: _submit,
        onToggleRecovery: _toggleRecovery,
        onPickFile: widget.sources.pickFile == null ? null : _pickBackup,
        onPickDrive: widget.sources.drive == null ? null : _pickDrive,
        onBack: _back,
        about: _about,
        onPickKept:
            widget.startup.state is Locked &&
                widget.startup.keptBeforeRestore().isNotEmpty
            ? _pickKept
            : null,
      );
    } else if (_recovery) {
      form = RecoveryView(
        code: _password,
        busy: _busy,
        problem: _problem,
        onSubmit: _submit,
        onPassword: _toggleRecovery,
        onBack: _back,
      );
    } else {
      form = UnlockView(
        password: _password,
        busy: _busy,
        problem: _problem,
        onSubmit: _submit,
        onRecovery: _toggleRecovery,
        onDevice: _biometric ? _unlockWithDevice : null,
        onBack: _back,
      );
    }
    // Back from the backup form returns to the first screen.
    return PopScope(
      canPop: !_restoring,
      onPopInvokedWithResult: (popped, _) {
        if (popped) return;
        if (widget.startup.state is Locked) {
          _keepLedger();
          return;
        }
        setState(() {
          _restoring = false;
          _recovery = false;
          _problem = null;
        });
      },
      child: form,
    );
  }
}
