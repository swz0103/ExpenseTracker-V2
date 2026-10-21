import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_backup.dart';

import '../platform.dart';
import '../startup.dart';
import 'lock/create_view.dart';
import 'lock/lock_parts.dart';
import 'lock/recovery_view.dart';
import 'lock/restore_view.dart';
import 'lock/unlock_view.dart';
import 'lock/welcome_view.dart';

/// The first screen of the phone app. A new ledger starts with one tap,
/// without a password (one can be set first, or later in settings), or
/// from a backup. A ledger with a password asks for it, a fingerprint or
/// the recovery code; one without opens by itself.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.startup});

  final Startup startup;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _password = TextEditingController();
  final _again = TextEditingController();
  final _file = TextEditingController();
  var _recovery = false;

  /// Restoring a backup instead of creating an empty ledger.
  var _restoring = false;

  /// Setting a password before starting a new ledger.
  var _withPassword = false;
  var _busy = false;
  String? _problem;

  /// The copy of the backup chosen with the file picker, in the cache.
  String? _picked;

  bool get _creating =>
      widget.startup.state is NeedsSetup && !_restoring && _withPassword;

  /// The first screen of a new ledger, before any choice.
  bool get _welcome =>
      widget.startup.state is NeedsSetup && !_restoring && !_withPassword;

  /// A ledger without a password, opening by itself.
  bool get _quiet =>
      widget.startup.state is Locked && widget.startup.passwordless;

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

  /// Starts a new ledger once the opening animation has played, unless
  /// the person chose to restore a backup instead.
  Timer? _autoStart;

  @override
  void initState() {
    super.initState();
    if (_welcome) {
      _autoStart = Timer(const Duration(milliseconds: 1600), () {
        if (mounted && _welcome) unawaited(_start());
      });
      return;
    }
    if (_quiet) {
      _busy = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openQuietly());
      });
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
    _autoStart?.cancel();
    _password.dispose();
    _again.dispose();
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
    if (_creating && secret != _again.text) {
      setState(() => _problem = '兩次輸入的密碼不一樣');
      return;
    }
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
      if (!_creating) {
        await (_recovery
            ? startup.unlockWithRecovery(secret.trim())
            : startup.unlockWithPassword(secret));
        return;
      }
      await startup.setUp(secret);
    } on BackupException catch (error) {
      _fail('無法讀取這個備份（${error.problem.name}）');
    } on FileSystemException {
      _fail('找不到這個備份檔');
    } on KeyringException catch (error) {
      _fail(switch (error.error) {
        KeyringError.weakPassword => '密碼至少要 6 個字',
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
    final path = await androidPickFile();
    if (path == null || !mounted) return;
    _picked = path;
    setState(() => _file.text = path);
  }

  void _fail(String problem) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = problem;
    });
  }

  /// Back from the password or backup form to the first screen; only a
  /// ledger not made yet has one.
  VoidCallback? get _back => widget.startup.state is NeedsSetup
      ? () => setState(() {
          _restoring = false;
          _withPassword = false;
          _recovery = false;
          _problem = null;
        })
      : null;

  /// Between the password and the recovery code.
  void _toggleRecovery() => setState(() {
    _recovery = !_recovery;
    _password.clear();
    _problem = null;
  });

  @override
  Widget build(BuildContext context) {
    // A new ledger starts by itself, without a password: one can be set
    // later in settings. Until then the opening animation plays, with a
    // way to restore a backup instead.
    if (_welcome && _problem == null) {
      return LockSplash(
        onRestore: _busy
            ? null
            : () {
                _autoStart?.cancel();
                setState(() => _restoring = true);
              },
      );
    }
    if (_welcome) {
      return WelcomeView(
        busy: _busy,
        problem: _problem,
        onStart: _start,
        onWithPassword: () => setState(() => _withPassword = true),
        onRestore: () => setState(() => _restoring = true),
      );
    }
    if (_quiet && _problem == null) return const LockSplash();
    final Widget form;
    if (_creating) {
      form = CreateView(
        password: _password,
        again: _again,
        busy: _busy,
        problem: _problem,
        onSubmit: _submit,
        onBack: _back,
      );
    } else if (_restoring) {
      form = RestoreView(
        file: _file,
        secret: _password,
        recovery: _recovery,
        busy: _busy,
        problem: _problem,
        onSubmit: _submit,
        onToggleRecovery: _toggleRecovery,
        onPickFile: Platform.isAndroid ? _pickBackup : null,
        onBack: _back,
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
    // Back from the password or backup form returns to the first screen.
    final away = _withPassword || _restoring;
    return PopScope(
      canPop: !away,
      onPopInvokedWithResult: (popped, _) {
        if (popped) return;
        setState(() {
          _withPassword = false;
          _restoring = false;
          _problem = null;
        });
        // Back on the opening screen: a new ledger is not started behind
        // the person's back; the welcome choices show instead.
        if (widget.startup.state is NeedsSetup) {
          setState(() => _problem = '');
        }
      },
      child: form,
    );
  }
}
