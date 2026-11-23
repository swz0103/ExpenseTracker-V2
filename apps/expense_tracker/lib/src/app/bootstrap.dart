import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

import '../../design_system/display/amount.dart';
import 'android/scanner_adapter.dart';
import 'app.dart';
import 'ledger_session.dart';
import 'lifecycle_services.dart';
import '../core/ledger/persistence/sql_ledger_data_source.dart';
import '../core/design_system/design_system.dart';
import '../core/ledger/ledger.dart';
import '../features/reminders/model/inbox_apply.dart';
import '../features/backup/model/restore_sources.dart';
import '../features/lock/ui/lock_screen.dart';
import '../features/lock/ui/views/new_password_view.dart';
import '../core/messages/key_messages.dart';
import '../core/platform/memory_keystore.dart';
import '../core/design_system/recovery_code.dart';
import 'shell.dart';
import 'platform.dart';
import '../core/platform/preferences.dart';
import '../core/platform/screen_privacy.dart';
import '../features/settings/ui/update_panel.dart';
import '../features/settings/model/platform_services.dart';
import '../core/platform/startup.dart';

/// The only production composition (code audit C-01): the encrypted ledger
/// in [directory], opened through [Startup]. The memory preview is not
/// reachable from here; a test walks the imports to keep it that way.
/// Every password set is held to the vault's one policy
/// (`PasswordPolicy.standard`); a ledger opened without a password keeps
/// its key sealed by the Android Keystore, never in plain form.
Startup productionStartup(Directory directory, {DeviceUnlock? device}) =>
    Startup(
      LedgerVault(directory, codec: KeyringCodec()),
      device: device,
      check: SqlLedgerDataSource.check,
      quickKey: Platform.isAndroid
          ? const KeystoreQuickKey()
          : MemoryKeystore.instance,
    );

/// Where this device keeps the ledger: the app's private folder on
/// Android, a folder in the home directory on desktop development builds.
Future<Directory> applicationDirectory() async {
  if (Platform.isAndroid) return androidFilesDirectory();
  final home = Platform.isWindows
      ? Platform.environment['APPDATA']
      : Platform.environment['HOME'];
  if (Platform.isIOS || home == null) {
    throw UnsupportedError('No ledger directory on this platform yet.');
  }
  return Directory('$home/.expense_tracker_v2');
}

/// Follows [startup]: the lock screen until a ledger is open, then the
/// app on that ledger.
class VaultRoot extends StatelessWidget {
  const VaultRoot({
    super.key,
    required this.startup,
    required this.preferences,
    this.privacy,
  });

  final Startup startup;

  /// Hiding the screens from screenshots, on Android.
  final ScreenPrivacy? privacy;
  final Preferences preferences;

  @override
  Widget build(BuildContext context) => ExpenseApp(
    preferences: preferences,
    cover: Platform.isAndroid,
    systemHides: Platform.isAndroid ? androidHidesRecents : null,
    home: ListenableBuilder(
      listenable: startup,
      builder: (context, _) => switch (startup.state) {
        Ready(:final vault) => OpenedLedger(
          key: ObjectKey(vault),
          startup: startup,
          vault: vault,
          privacy: privacy,
          preferences: preferences,
        ),
        final state => LockScreen(
          key: ValueKey(state.runtimeType),
          startup: startup,
          sources: Platform.isAndroid
              ? const RestoreSources(
                  pickFile: androidPickFile,
                  drive: androidDrive,
                  cacheDirectory: androidCacheDirectory,
                )
              : const RestoreSources(),
        ),
      },
    ),
  );
}

/// The app on an unlocked [vault]: it loads the book, then shows it. A
/// ledger just created shows its recovery code first.
class OpenedLedger extends StatefulWidget {
  const OpenedLedger({
    super.key,
    required this.startup,
    required this.vault,
    required this.preferences,
    this.privacy,
  });

  final Startup startup;
  final OpenVault vault;
  final ScreenPrivacy? privacy;
  final Preferences preferences;

  @override
  State<OpenedLedger> createState() => _OpenedLedgerState();
}

class _OpenedLedgerState extends State<OpenedLedger>
    with WidgetsBindingObserver {
  /// A ledger just started on this phone: the app shows its tour.
  late final _fresh = widget.startup.takeFresh();

  /// What runs beside the ledger: prices, backups, the calendar,
  /// notifications, the widget, updates and the lock when away.
  late final _services = LifecycleServices(
    startup: widget.startup,
    vault: widget.vault,
    preferences: widget.preferences,
    android: Platform.isAndroid,
    say: (note) {
      if (mounted) showNote(context, note);
    },
    offerUpdate: (update) async {
      if (mounted) await showUpdatePanel(context, update);
    },
  );

  /// Opening the book: load, inbox, health check, what is due.
  late final _session = LedgerSession(
    load: _services.dataSource.load,
    inbox: Platform.isAndroid
        ? () async {
            final inbox = await LedgerInbox.open(
              widget.startup.directory,
              widget.vault.keys,
            );
            return (read: inbox.read, remove: inbox.remove);
          }
        : null,
  );

  late final Future<Ledger> _ledger = _open();

  Future<Ledger> _open() async {
    final start = await _session.open();
    await _services.start(start.ledger);
    _afterFrame(() {
      if (start.inbox case final inbox?) _tellInbox(inbox);
      _tellBooked(start.booked);
    });
    return start.ledger;
  }

  void _afterFrame(VoidCallback then) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) then();
      });

  /// What the inbox booked, and what it could not, listed once.
  void _tellInbox(InboxOutcome outcome) {
    if (outcome.booked > 0) {
      showNote(
        context,
        '已依通知上的確認記下 ${countOf(outcome.booked, CountUnit.entries)}',
      );
    }
    if (outcome.review.isEmpty) return;
    unawaited(_notice('通知上的確認', outcome.review.join('\n')));
  }

  void _tellBooked(int booked) {
    if (booked > 0) {
      showNote(context, '已自動記下 ${countOf(booked, CountUnit.entries)}定期交易');
    }
  }

  Future<void> _notice(String title, String text) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final code = widget.startup.takeRecoveryCode();
    final reset = widget.startup.takeKeysReset();
    _afterFrame(() {
      if (code != null) {
        unawaited(
          reset
              ? showRecoveryCode(context, code, why: KeyWords.resetDone)
              : widget.startup.passwordless
              ? showRecoveryCode(
                  context,
                  code,
                  why: '帳本每天自動備份到 Google，換手機還原時要輸入它',
                )
              : showRecoveryCode(context, code),
        );
      }
    });
  }

  @override
  void dispose() {
    _services.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Locks the ledger when the app comes back after a while away; books
  /// what fell due meanwhile.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        unawaited(_services.paused());
      case AppLifecycleState.resumed:
        _ledger.then((ledger) {
          ledger.checkDay();
          if (mounted) _tellBooked(_session.bookDue(ledger));
        }).ignore();
        unawaited(_services.resumed());
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final startup = widget.startup;
    // Opened by the recovery code: a new password before anything else.
    if (startup.needsNewPassword) {
      return NewPasswordView(
        onSet: startup.setNewPassword,
        onNoPassword: startup.openWithoutPassword,
      );
    }
    return _book(context);
  }

  Widget _book(BuildContext context) => FutureBuilder(
    future: _ledger,
    builder: (context, snapshot) {
      final ledger = snapshot.data;
      if (snapshot.hasError) {
        return Scaffold(body: Center(child: Text('無法讀取帳本：${snapshot.error}')));
      }
      if (ledger == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return AppShell(
        ledger: ledger,
        tour: _fresh,
        services: PlatformServices(
          backupManager: _services.backupManager,
          calendar: _services.calendar,
          privacy: widget.privacy,
          preferences: widget.preferences,
          notifier: _services.notifier,
          quick: Platform.isAndroid ? quickAction : null,
          receipts: _services.receipts,
          drive: _services.drive,
          phone: _services.phone,
          market: _services.market,
          update: _services.update,
          scanQr: Platform.isAndroid ? androidScanQr : null,
        ),
      );
    },
  );
}
