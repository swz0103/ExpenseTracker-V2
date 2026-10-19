import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_backup.dart';

import '../look/glyphs.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../platform.dart';
import '../startup.dart';

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

  @override
  void initState() {
    super.initState();
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
    _password.dispose();
    _again.dispose();
    _file.dispose();
    super.dispose();
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
    setState(() => _file.text = path);
  }

  void _fail(String problem) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = problem;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_welcome) return _welcomeScreen();
    if (_quiet && _problem == null) {
      return const Scaffold(
        backgroundColor: Hue.paper,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final creating = _creating;
    final empty = widget.startup.state is NeedsSetup;
    final title = creating
        ? '建立帳本'
        : _restoring
        ? '從備份還原'
        : '打開帳本';
    final hint = creating
        ? '帳本會以這組密碼加密，只存在這台裝置上。至少 6 個字。'
        : _restoring
        ? '輸入備份檔的位置，和那個帳本的密碼或救援碼。'
        : _recovery
        ? '輸入建立帳本時拿到的救援碼。'
        : '輸入帳本密碼。';
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
      },
      child: Scaffold(
        backgroundColor: Hue.paper,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(
                      child: IconBadge(Glyph.wallet, Hue.accent, size: 64),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      hint,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Hue.muted),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Hue.hero,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Column(
                        children: [
                          if (_restoring) ...[
                            if (Platform.isAndroid)
                              OutlinedButton(
                                onPressed: _busy ? null : _pickBackup,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(44),
                                ),
                                child: Text(
                                  _file.text.isEmpty ? '選擇備份檔' : '已選好備份檔',
                                ),
                              )
                            else
                              _Secret(
                                controller: _file,
                                hint: '備份檔路徑，例如 C:\\Users\\me\\記帳本.etbk',
                                hidden: false,
                              ),
                            const SizedBox(height: 8),
                          ],
                          _Secret(
                            controller: _password,
                            hint: _recovery ? '救援碼' : '密碼',
                            hidden: !_recovery,
                            onSubmitted: creating ? null : _submit,
                          ),
                          if (creating) ...[
                            const SizedBox(height: 8),
                            _Secret(
                              controller: _again,
                              hint: '再輸入一次密碼',
                              hidden: true,
                              onSubmitted: _submit,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_problem case final problem?)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          problem,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Hue.danger),
                        ),
                      ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: Hue.accent,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Hue.white,
                              ),
                            )
                          : Text(
                              creating
                                  ? '建立'
                                  : _restoring
                                  ? '還原'
                                  : '打開',
                            ),
                    ),
                    if (!creating)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _recovery = !_recovery;
                                _password.clear();
                                _problem = null;
                              }),
                        child: Text(_recovery ? '改用密碼' : '忘記密碼？用救援碼'),
                      ),
                    if (_biometric && !_recovery)
                      TextButton(
                        onPressed: _busy ? null : _unlockWithDevice,
                        child: const Text('用指紋或臉部解鎖'),
                      ),
                    if (empty)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _restoring = false;
                                _withPassword = false;
                                _recovery = false;
                                _problem = null;
                              }),
                        child: const Text('返回'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _welcomeScreen() {
    final problem = _problem;
    return Scaffold(
      backgroundColor: Hue.paper,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                    child: IconBadge(Glyph.wallet, Hue.accent, size: 84),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '歡迎使用記帳本',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '帳本只存在這台手機，並且加密保存。\n不用註冊，現在就能開始記帳。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Hue.muted, height: 1.5),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _busy ? null : _start,
                    style: FilledButton.styleFrom(
                      backgroundColor: Hue.accent,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Hue.white,
                            ),
                          )
                        : const Text(
                            '開始記帳',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                  if (problem != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        problem,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Hue.danger),
                      ),
                    ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _withPassword = true),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text('先設定密碼'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _restoring = true),
                    child: const Text('從備份還原'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '之後可以在「設定」加上密碼或指紋解鎖。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Hue.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Secret extends StatelessWidget {
  const _Secret({
    required this.controller,
    required this.hint,
    required this.hidden,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final bool hidden;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final submit = onSubmitted;
    return TextField(
      controller: controller,
      obscureText: hidden,
      autocorrect: false,
      enableSuggestions: false,
      onSubmitted: submit == null ? null : (_) => submit(),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Hue.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
