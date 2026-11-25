import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/design_system/dialogs.dart';
import '../../../../core/diagnostics/error_log.dart';
import '../../../../core/messages/key_failures.dart';
import '../../../../core/messages/key_messages.dart';
import 'lock_parts.dart';

/// Asked as soon as the recovery code (or a backup without the password)
/// opened the ledger: a new password, twice, held to the password rule.
/// It cannot be closed or gone back from; the only other way on is to
/// choose, and confirm, opening the ledger without a password.
class NewPasswordView extends StatefulWidget {
  const NewPasswordView({
    super.key,
    required this.onSet,
    required this.onNoPassword,
  });

  /// Sets the password; throws when it cannot.
  final Future<void> Function(String password) onSet;

  /// Opens the ledger without a password from now on.
  final Future<void> Function() onNoPassword;

  @override
  State<NewPasswordView> createState() => _NewPasswordViewState();
}

class _NewPasswordViewState extends State<NewPasswordView> {
  final _next = TextEditingController();
  final _again = TextEditingController();
  var _busy = false;
  String? _problem;

  @override
  void dispose() {
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() step) async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await step();
    } on Object catch (error) {
      ErrorLog.instance.record(KeyWords.newPasswordTitle, error);
      if (mounted) {
        setState(() {
          _busy = false;
          _problem = describeKeyProblem(error);
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_next.text != _again.text) {
      setState(() => _problem = KeyWords.mismatch);
      return;
    }
    if (passwordRefusal(_next.text) case final refusal?) {
      setState(() => _problem = refusal);
      return;
    }
    await _run(() => widget.onSet(_next.text));
  }

  Future<void> _noPassword() async {
    final ok = await confirm(
      context,
      KeyWords.noPasswordConfirm,
      KeyWords.noPasswordGo,
      danger: true,
      body: KeyWords.noPasswordConfirmBody,
    );
    if (ok && mounted) await _run(widget.onNoPassword);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: LockForm(
        title: KeyWords.newPasswordTitle,
        hint: KeyWords.newPasswordHint(passwordRule),
        fields: [
          PasswordField(
            controller: _next,
            hint: KeyWords.newPassword,
            boxed: true,
          ),
          PasswordField(
            controller: _again,
            hint: KeyWords.again,
            boxed: true,
            onSubmitted: _submit,
          ),
        ],
        action: KeyWords.setPassword,
        actionKey: Keys.newPassword,
        busy: _busy,
        onSubmit: _submit,
        problem: _problem,
        extras: [
          LockLink(
            KeyWords.noPassword,
            _noPassword,
            busy: _busy,
            key: Keys.noPassword,
          ),
        ],
      ),
    );
  }
}
