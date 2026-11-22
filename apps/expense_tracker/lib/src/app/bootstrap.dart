import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

import 'android/scanner_adapter.dart';
import 'app.dart';
import 'ledger_session.dart';
import 'lifecycle_services.dart';
import 'load_failed_page.dart';
import '../core/ledger/persistence/sql_ledger_data_source.dart';
import '../core/ledger/persistence/quarantine.dart';
import '../core/design_system/design_system.dart';
import '../core/diagnostics/error_log.dart';
import '../core/messages/loading_messages.dart';
import '../core/messages/problem_messages.dart';
import '../features/backup/ui/backup_section.dart' show restoreFromBackup;
import '../core/ledger/ledger.dart';
import '../features/reminders/model/inbox_apply.dart';
import '../features/backup/model/restore_sources.dart';
import '../features/lock/ui/lock_screen.dart';
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
Startup productionStartup(Directory directory, {DeviceUnlock? device}) =>
    Startup(
      LedgerVault(directory, codec: KeyringCodec(minimumPassword: 6)),
      device: device,
      check: SqlLedgerDataSource.check,
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
    quarantined: () => _services.dataSource.quarantined,
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

  late Future<Ledger> _ledger = _open();

  Future<Ledger> _open() async {
    final start = await _session.open();
    await _services.start(start.ledger);
    _afterFrame(() {
      if (start.inbox case final inbox?) _tellInbox(inbox);
      _tellBooked(start.booked);
      if (start.quarantined.isNotEmpty) {
        unawaited(_tellQuarantined(start.quarantined));
      }
    });
    return start.ledger;
  }

  /// Opens the book again, after it could not be opened.
  void _retry() => setState(() => _ledger = _open());

  /// Hands the person the diagnostics of this opening: the rows set
  /// aside, or what kept the book shut, with no amount, note or name.
  Future<void> _exportReport({
    List<QuarantinedRow> rows = const [],
    Object? failure,
  }) async {
    try {
      final saved = await _services.backupManager.exportFile(
        openingReportName,
        openingReport(
          rows: rows,
          failure: failure == null ? null : ErrorLog.describe(failure),
          log: ErrorLog.instance.text,
        ),
      );
      if (mounted && saved) showNote(context, quarantineExported);
    } on Object catch (error) {
      ErrorLog.instance.record(loadFailedExport, error);
      if (mounted) showNote(context, describeProblem(error));
    }
  }

  /// Tells how many rows were set aside, with a way to report them, to
  /// restore a backup, or to go on with the rest of the book.
  Future<void> _tellQuarantined(List<QuarantinedRow> rows) async {
    final restore = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(quarantineTitle(rows.length)),
        content: Text(quarantineBody(rows)),
        actions: [
          TextButton(
            onPressed: () => unawaited(_exportReport(rows: rows)),
            child: const Text(quarantineExport),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(quarantineRestore),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(quarantineContinue),
          ),
        ],
      ),
    );
    if (restore == true && mounted) {
      await restoreFromBackup(context, _services.backupManager);
    }
  }

  /// From a book that could not be opened, to the lock screen's restore:
  /// a copy of this ledger is kept first when it can be, and the restore
  /// is offered all the same when it cannot.
  Future<void> _restoreAfterFailure() async {
    try {
      await _services.backupManager.restoreAnother();
    } on Object catch (error) {
      ErrorLog.instance.record(loadFailedRestore, error);
      widget.startup.lockToRestore();
    }
  }

  void _afterFrame(VoidCallback then) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) then();
      });

  /// What the inbox booked, and what it could not, listed once.
  void _tellInbox(InboxOutcome outcome) {
    if (outcome.booked > 0) {
      showNote(context, '已依通知上的確認記下 ${outcome.booked} 筆');
    }
    if (outcome.review.isEmpty) return;
    unawaited(_notice('通知上的確認', outcome.review.join('\n')));
  }

  void _tellBooked(int booked) {
    if (booked > 0) showNote(context, '已自動記下 $booked 筆定期交易');
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
    final recovered = widget.startup.takeRecoveryNotice();
    _afterFrame(() {
      if (code != null) {
        unawaited(
          widget.startup.passwordless
              ? showRecoveryCode(
                  context,
                  code,
                  why: '帳本每天自動備份到 Google，換手機還原時要輸入它',
                )
              : showRecoveryCode(context, code),
        );
      }
      if (recovered) {
        unawaited(_notice('已用救援碼打開', '現在打開 App 不需要密碼。想要密碼的話，可以到「設定」重新設定。'));
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
  Widget build(BuildContext context) => FutureBuilder(
    future: _ledger,
    builder: (context, snapshot) {
      final ledger = snapshot.data;
      if (snapshot.hasError) {
        final error = snapshot.error!;
        return LoadFailedPage(
          onRetry: _retry,
          onRestore: _restoreAfterFailure,
          onExport: () => _exportReport(failure: error),
        );
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
