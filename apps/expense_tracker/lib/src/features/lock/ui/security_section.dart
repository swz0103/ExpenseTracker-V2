import 'package:flutter/material.dart';
import 'package:shell/setting_topic.dart';

import '../../backup/model/backup_manager.dart';
import '../../../core/design_system/dialogs.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/messages/key_messages.dart';
import '../../../core/messages/lock_messages.dart';
import '../../../core/platform/preferences.dart';
import '../../../core/platform/preference_choices.dart';
import '../../../core/messages/problem_messages.dart';
import '../../../core/platform/screen_privacy.dart';
import '../../../core/design_system/recovery_code.dart';
import '../../../core/design_system/settings_colors.dart';
import '../../../core/diagnostics/error_log.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/formatting/words.dart';

/// 安全: the password, the fingerprint, the recovery code, the backup
/// passphrase, how soon the ledger locks by itself, hiding the screens,
/// resetting the keys, and locking the ledger now.
class SecuritySection extends StatefulWidget {
  const SecuritySection({
    super.key,
    this.backupManager,
    this.privacy,
    this.preferences,
  });

  final BackupManager? backupManager;
  final ScreenPrivacy? privacy;

  /// Where the auto-lock choice is kept.
  final Preferences? preferences;

  // What search finds here (N8): each topic marks its card.
  static const topics = [
    SecurityTopics.password,
    SecurityTopics.fingerprint,
    SecurityTopics.autoLock,
    SecurityTopics.recovery,
    SecurityTopics.passphrase,
    SecurityTopics.hideScreen,
    SecurityTopics.reset,
    SecurityTopics.lockNow,
  ];

  /// The [topics] shown with these services: the fingerprint only where
  /// the phone has one, 自動上鎖 and 現在鎖上 only with a password, 隱藏畫面
  /// only where the screen can be hidden (review 39 #4).
  static List<SettingTopic> offered({
    BackupManager? backupManager,
    ScreenPrivacy? privacy,
    Preferences? preferences,
  }) {
    final locked = backupManager?.hasPassword ?? false;
    return [
      if (backupManager != null) ...[
        SecurityTopics.password,
        if (backupManager.canUseFingerprint) SecurityTopics.fingerprint,
        if (preferences != null && locked) SecurityTopics.autoLock,
        SecurityTopics.recovery,
        SecurityTopics.passphrase,
      ],
      if (privacy != null) SecurityTopics.hideScreen,
      if (backupManager != null) SecurityTopics.reset,
      if (locked) SecurityTopics.lockNow,
    ];
  }

  @override
  State<SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<SecuritySection> {
  /// Sets or changes the password. Every problem (the two new ones differ,
  /// the new one is against the rule, the current one is wrong) is said in
  /// the panel, with what was typed kept.
  Future<void> _changePassword(BackupManager backupManager) async {
    final first = !backupManager.hasPassword;
    final done = await showPanel<bool>(
      context,
      (_) => _SecretPanel(
        glyph: Glyph.key,
        color: SettingsColors.password,
        title: first ? KeyWords.setPassword : KeyWords.changePassword,
        detail: first
            ? backupManager.passwordRule
            : '${backupManager.passwordRule}。${KeyWords.passwordScope}',
        askCurrent: !first,
        action: first ? KeyWords.set : KeyWords.change,
        actionKey: Keys.changePassword,
        refuse: backupManager.refusePassword,
        submit: (current, next) => first
            ? backupManager.setPassword(next)
            : backupManager.changePassword(current, next),
      ),
    );
    if (done != true || !mounted) return;
    if (first) {
      try {
        // A ledger started without a password has had no code to show yet.
        final code = await backupManager.newRecoveryCode();
        if (mounted) {
          await showRecoveryCode(context, code, why: KeyWords.passwordFirstWhy);
        }
      } on Object catch (error) {
        ErrorLog.instance.record('變更密碼', error);
        if (mounted) {
          showNote(context, problemNote(KeyWords.notReplaced, error));
        }
      }
    }
    if (!mounted) return;
    setState(() {});
    showNote(context, first ? KeyWords.passwordSet : KeyWords.passwordChanged);
  }

  Future<void> _newRecovery(BackupManager backupManager) async {
    final ok = await confirm(
      context,
      KeyWords.recoveryConfirm,
      KeyWords.replace,
      danger: true,
      body: KeyWords.recoveryConfirmBody,
    );
    if (!ok) return;
    try {
      final code = await backupManager.newRecoveryCode();
      if (mounted) await showRecoveryCode(context, code);
    } on Object catch (error) {
      ErrorLog.instance.record('變更密碼', error);
      if (mounted) {
        showNote(context, problemNote(KeyWords.notReplaced, error));
      }
    }
  }

  /// Sets the backup passphrase, or, when one is set, sets another or
  /// stops using it.
  Future<void> _passphrase(BackupManager backupManager) async {
    final has = backupManager.hasBackupPassphrase;
    final done = await showPanel<bool>(
      context,
      (context) => _SecretPanel(
        glyph: Glyph.safe,
        color: SettingsColors.backup,
        title: KeyWords.passphrase,
        detail: KeyWords.passphraseDetail(backupManager.passphraseRule),
        askCurrent: false,
        action: KeyWords.set,
        refuse: backupManager.refusePassphrase,
        submit: (_, next) => backupManager.setBackupPassphrase(next),
        extra: has
            ? PanelButton(
                KeyWords.remove,
                onTap: () => Navigator.of(context).pop(false),
              )
            : null,
      ),
    );
    if (!mounted || done == null) return;
    if (done) {
      setState(() {});
      showNote(context, KeyWords.passphraseSet);
      return;
    }
    final ok = await confirm(
      context,
      KeyWords.passphraseRemove,
      KeyWords.remove,
      danger: true,
      body: KeyWords.passphraseRemoveBody,
    );
    if (!ok) return;
    try {
      await backupManager.removeBackupPassphrase();
      if (!mounted) return;
      setState(() {});
      showNote(context, KeyWords.passphraseRemoved);
    } on Object catch (error) {
      ErrorLog.instance.record('備份密碼', error);
      if (mounted) showNote(context, _said(error));
    }
  }

  /// Says what resetting the keys does and does not, asks for the current
  /// password when there is one, then resets: the app opens the ledger
  /// afresh and shows the new recovery code.
  Future<void> _resetKeys(BackupManager backupManager) async {
    final done = await showPanel<bool>(
      context,
      (_) => _SecretPanel(
        glyph: Glyph.shield,
        color: SettingsColors.warning,
        title: KeyWords.reset,
        detail: KeyWords.resetWhy,
        askCurrent: backupManager.hasPassword,
        askNew: false,
        action: KeyWords.resetGo,
        actionKey: Keys.resetGo,
        refuse: backupManager.refusePassword,
        submit: (current, _) =>
            // Exception to undo rule: asked by this panel, which takes the
            // current password and its own 重設 (KeyWords.resetGo).
            backupManager.resetKeys(backupManager.hasPassword ? current : null),
      ),
    );
    // The ledger opened afresh on its new keys: the pages over the old
    // one go, so nothing is left working on the closed one.
    if (done == true && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  /// Turns screen hiding on or off.
  Future<void> _hideScreen(ScreenPrivacy privacy, bool on) async {
    try {
      await privacy.turn(on: on);
    } on Object catch (error) {
      ErrorLog.instance.record(LockWords.hideScreenHeading, error);
      if (mounted) showNote(context, LockWords.hideScreenFailed);
    }
    if (mounted) setState(() {});
  }

  /// Turns opening with the fingerprint on (the phone asks for it once)
  /// or off. Turning the phone's prompt down changes nothing and is not
  /// a fault: nothing is said and nothing noted.
  Future<void> _fingerprint(BackupManager backupManager, bool on) async {
    try {
      final done = await backupManager.turnFingerprint(on: on);
      if (!mounted) return;
      setState(() {});
      if (done) {
        showNote(
          context,
          on ? LockWords.fingerprintTurnedOn : LockWords.fingerprintTurnedOff,
        );
      }
    } on Object catch (error) {
      ErrorLog.instance.record(LockWords.fingerprintSettingHeading, error);
      if (mounted) {
        setState(() {});
        showNote(context, LockWords.fingerprintNotTurned);
      }
    }
  }

  /// How long away locks the ledger, from the one table of choices.
  void _pickAutoLock(Preferences preferences) {
    showCenterPanel(
      context,
      glyph: Glyph.hourglass,
      color: SettingsColors.security,
      title: LockWords.autoLock,
      detail: LockWords.autoLockWhy,
      body: (context) => ListenableBuilder(
        listenable: preferences.watch(const {PreferenceTopic.lock}),
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final choice in AutoLock.values)
              _Choice(
                key: Keys.autoLockChoice(choice.name),
                label: choice.label,
                chosen: choice == preferences.autoLock,
                onTap: () => preferences.update(autoLock: choice),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final backupManager = widget.backupManager;
    final privacy = widget.privacy;
    final preferences = widget.preferences;
    return CardGrid([
      if (backupManager != null) ...[
        SettingCard(
          topic: SecurityTopics.password,
          key: Keys.password,
          glyph: Glyph.key,
          color: backupManager.passwordBelowRule
              ? SettingsColors.warning
              : SettingsColors.password,
          title: '密碼',
          detail: !backupManager.hasPassword
              ? '還沒設定 · 點了設定'
              : backupManager.passwordBelowRule
              ? KeyWords.passwordBelowRule
              : '已設定 · 點了變更',
          onTap: () => _changePassword(backupManager),
        ),
        // Only where the phone can confirm one and there is a password
        // for it to stand in for.
        if (backupManager.canUseFingerprint)
          SettingCard(
            topic: SecurityTopics.fingerprint,
            key: Keys.fingerprintSwitch,
            glyph: Glyph.shield,
            color: SettingsColors.security,
            title: LockWords.fingerprint,
            detail: backupManager.fingerprintOn
                ? LockWords.fingerprintOn
                : LockWords.fingerprintOff,
            value: backupManager.fingerprintOn,
            onChanged: (on) => _fingerprint(backupManager, on),
            onTap: () =>
                _fingerprint(backupManager, !backupManager.fingerprintOn),
          ),
        // A ledger without a password never locks.
        if (preferences != null && backupManager.hasPassword)
          ListenableBuilder(
            listenable: preferences.watch(const {PreferenceTopic.lock}),
            builder: (context, _) => SettingCard(
              topic: SecurityTopics.autoLock,
              key: Keys.autoLock,
              glyph: Glyph.hourglass,
              color: SettingsColors.security,
              title: LockWords.autoLock,
              detail: LockWords.autoLockDetail(preferences.autoLock),
              onTap: () => _pickAutoLock(preferences),
            ),
          ),
        SettingCard(
          topic: SecurityTopics.recovery,
          glyph: Glyph.lifebuoy,
          color: SettingsColors.recovery,
          title: '救援碼',
          detail: '忘記密碼、換手機用',
          onTap: () => _newRecovery(backupManager),
        ),
        SettingCard(
          topic: SecurityTopics.passphrase,
          key: Keys.passphrase,
          glyph: Glyph.safe,
          color: SettingsColors.backup,
          title: KeyWords.passphrase,
          detail: backupManager.hasBackupPassphrase
              ? KeyWords.passphraseOn
              : KeyWords.passphraseOff,
          onTap: () => _passphrase(backupManager),
        ),
      ],
      if (privacy != null)
        SettingCard(
          topic: SecurityTopics.hideScreen,
          key: Keys.hideScreen,
          glyph: Glyph.eyeOff,
          color: SettingsColors.appearance,
          // The recent apps list never shows the ledger, and the lock
          // screen is never in a screenshot, switched on or not: this
          // stops screenshots and recordings of the open ledger too.
          title: LockWords.hideScreen,
          detail: privacy.on ? LockWords.hideScreenOn : LockWords.hideScreenOff,
          value: privacy.on,
          onChanged: (on) => _hideScreen(privacy, on),
          onTap: () => _hideScreen(privacy, !privacy.on),
        ),
      if (backupManager != null)
        SettingCard(
          topic: SecurityTopics.reset,
          key: Keys.resetKeys,
          glyph: Glyph.shield,
          color: SettingsColors.warning,
          title: KeyWords.reset,
          detail: KeyWords.resetDetail,
          onTap: () => _resetKeys(backupManager),
        ),
      if (backupManager != null && backupManager.hasPassword)
        SettingCard(
          topic: SecurityTopics.lockNow,
          key: Keys.lockNow,
          glyph: Glyph.lock,
          color: SettingsColors.about,
          title: '現在鎖上',
          detail: '回到解鎖畫面',
          onTap: backupManager.lock,
        ),
    ]);
  }
}

/// One of the auto-lock choices: its words, ticked when it is the one in
/// force.
class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.label,
    required this.chosen,
    required this.onTap,
  });

  final String label;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: chosen,
    inMutuallyExclusiveGroup: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.large),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.s4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: chosen ? FontWeight.w700 : FontWeight.w500,
                    color: chosen
                        ? deepOf(SettingsColors.security)
                        : AppColors.ink,
                  ),
                ),
              ),
              if (chosen)
                const GlyphIcon(Glyph.check, color: SettingsColors.security),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Asks for a secret to set (twice), the current password first when
/// [askCurrent], or only the current password when not [askNew]. The
/// panel itself calls [submit] and stays open with every field as typed
/// when something is wrong, saying what under the fields: the new ones
/// differ, a new one is against the password rule, the current one is
/// wrong. Pops true once [submit] went through.
class _SecretPanel extends StatefulWidget {
  const _SecretPanel({
    required this.glyph,
    required this.color,
    required this.title,
    required this.detail,
    required this.askCurrent,
    required this.action,
    required this.submit,
    required this.refuse,
    this.askNew = true,
    this.actionKey,
    this.extra,
  });

  final Glyph glyph;
  final Color color;
  final String title;
  final String detail;
  final bool askCurrent;
  final bool askNew;
  final String action;
  final Key? actionKey;

  /// Does the change with the current and the new secret; throws when it
  /// cannot ([KeyRefused] says why in words).
  final Future<void> Function(String current, String next) submit;

  /// Why a new secret cannot be set, or null (the password rule).
  final String? Function(String secret) refuse;

  /// Another button beside the main one, such as 停用.
  final Widget? extra;

  @override
  State<_SecretPanel> createState() => _SecretPanelState();
}

class _SecretPanelState extends State<_SecretPanel> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  String? _problem;
  var _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (widget.askNew) {
      if (_next.text != _again.text) {
        setState(() => _problem = KeyWords.mismatch);
        return;
      }
      if (widget.refuse(_next.text) case final refusal?) {
        setState(() => _problem = refusal);
        return;
      }
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await widget.submit(_current.text, _next.text);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      ErrorLog.instance.record(widget.title, error);
      if (mounted) {
        setState(() {
          _busy = false;
          _problem = _said(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    Widget field(TextEditingController controller, String label) => Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          Space.s4,
          Space.s2,
          Space.s4,
          Space.s1,
        ),
        decoration: BoxDecoration(
          color: tintOf(color, 0.14),
          borderRadius: BorderRadius.circular(Radii.large),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: TextSize.small,
                fontWeight: FontWeight.w700,
                color: deepOf(color),
              ),
            ),
            PasswordField(controller: controller, hint: '', plain: true),
          ],
        ),
      ),
    );
    final extra = widget.extra;
    return CenterPanel(
      glyph: widget.glyph,
      color: color,
      title: widget.title,
      detail: widget.detail,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.askCurrent) field(_current, KeyWords.currentPassword),
          if (widget.askNew) ...[
            field(_next, KeyWords.newPassword),
            field(_again, KeyWords.again),
          ],
          if (_problem case final problem?) Text(problem, style: dangerText),
        ],
      ),
      actions: [
        PanelButton(
          Words.cancel,
          onTap: _busy ? null : () => Navigator.of(context).pop(),
        ),
        ?extra,
        PanelButton(
          widget.action,
          key: widget.actionKey,
          color: color,
          onTap: _busy ? null : _submit,
        ),
      ],
    );
  }
}

/// What the person is told of [error]: the keys' own words when they
/// refused, general ones otherwise.
String _said(Object error) =>
    // Exception to error words: a KeyRefused's message is the app's own
    // sentence (backup_manager.dart).
    error is KeyRefused ? error.message : KeyWords.notDone;
