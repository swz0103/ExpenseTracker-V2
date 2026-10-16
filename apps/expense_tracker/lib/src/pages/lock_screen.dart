import 'dart:io';

import 'package:backup_security/backup_security.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ledger_backup/ledger_backup.dart';

import '../look/glyphs.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../startup.dart';

/// The first screen of the phone app: a password to create the encrypted
/// ledger, or to open it; the recovery code opens it when the password is
/// forgotten.
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
  var _busy = false;
  String? _problem;

  bool get _creating => widget.startup.state is NeedsSetup && !_restoring;

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
        KeyringError.weakPassword => '密碼至少要 12 個字',
        KeyringError.wrongSecret => _recovery ? '救援碼不正確' : '密碼不正確',
        _ => '無法開啟帳本（${error.error.name}）',
      });
    } on Object catch (error) {
      _fail('無法開啟帳本（$error）');
    }
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
    final creating = _creating;
    final empty = widget.startup.state is NeedsSetup;
    final title = creating
        ? '建立帳本'
        : _restoring
        ? '從備份還原'
        : '打開帳本';
    final hint = creating
        ? '帳本會以這組密碼加密，只存在這台裝置上。'
        : _restoring
        ? '輸入備份檔的位置，和那個帳本的密碼或救援碼。'
        : _recovery
        ? '輸入建立帳本時拿到的救援碼。'
        : '輸入帳本密碼。';
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
                          _Secret(
                            controller: _file,
                            hint: '備份檔路徑，例如 /home/me/記帳本.etbk',
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
                  if (empty)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _restoring = !_restoring;
                              _recovery = false;
                              _problem = null;
                            }),
                      child: Text(_restoring ? '改為建立新帳本' : '從備份還原'),
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

/// Shows a new ledger's recovery code once; it is the only way in without
/// the password.
Future<void> showRecoveryCode(BuildContext context, String code) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('救援碼'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('忘記密碼時，只有這組救援碼能打開帳本。請抄下來放在安全的地方，它只會顯示這一次。'),
          const SizedBox(height: 14),
          SelectableText(
            code,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Clipboard.setData(ClipboardData(text: code)),
          child: const Text('複製'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('我已存好'),
        ),
      ],
    ),
  );
}
