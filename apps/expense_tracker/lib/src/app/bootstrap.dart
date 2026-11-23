import 'dart:async';
import 'dart:io';

import 'package:core/app_core.dart' show untilNextMidnight;
import 'package:flutter/material.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

import '../../design_system/display/amount.dart';
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
import '../features/lock/ui/views/new_password_view.dart';
import '../core/messages/key_messages.dart';
import '../core/diagnostics/error_steps.dart';
import '../core/design_system/feedback.dart';
import '../core/platform/app_lifecycle.dart';
import '../core/platform/away_clock.dart';
import '../core/platform/errands.dart';
import '../core/navigation/nav.dart' show AppRoute;
import '../core/platform/lock_gate.dart';
import '../core/platform/memory_keystore.dart';
import '../core/platform/quick_action.dart';
import '../core/platform/unlock_attempts.dart';
import '../core/widgets/lock_cover.dart';
import '../core/design_system/recovery_code.dart';
import 'shell.dart';
import 'platform.dart';
import '../core/platform/preferences.dart';
import '../core/platform/screen_privacy.dart';
import '../features/settings/ui/update_panel.dart';
import '../features/settings/model/platform_services.dart';
import '../core/platform/startup.dart';
import '../core/time/app_clock.dart';

/// The only production composition (code audit C-01): the encrypted ledger
/// in [directory], opened through [Startup]. The memory preview is not
/// reachable from here; a test walks the imports to keep it that way.
/// Every password set is held to the vault's one policy
/// (`PasswordPolicy.standard`); a ledger opened without a password keeps
/// its key sealed by the Android Keystore, never in plain form.
/// Wrong passwords are slowed down by the vault's one table
/// (`AttemptPolicy.standard`), the wait measured by [uptime] where the
/// phone has such a clock.
Startup productionStartup(
  Directory directory, {
  DeviceUnlock? device,
  UptimeSource? uptime,
}) => Startup(
  LedgerVault(directory, codec: KeyringCodec()),
  device: device,
  check: SqlLedgerDataSource.check,
  quickKey: Platform.isAndroid
      ? const KeystoreQuickKey()
      : MemoryKeystore.instance,
  uptime: uptime,
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

/// Follows [startup] through the one lock gate ([LockGate]): the lock
/// screen until a ledger is open, then the app on that ledger. Every
/// route, sheet and dialog lives in a navigator that belongs to one
/// opening of the ledger and is replaced when it ends, so nothing of a
/// closed ledger stays on screen or in the widget tree; while the gate
/// says the ledger may not be seen, a cover is drawn over everything.
class VaultRoot extends StatefulWidget {
  const VaultRoot({
    super.key,
    required this.startup,
    required this.preferences,
    this.privacy,
    this.quick,
    this.leave,
    this.awayClock,
  });

  final Startup startup;

  /// Hiding the screens from screenshots, on Android.
  final ScreenPrivacy? privacy;
  final Preferences preferences;

  /// What a shortcut, the widget or a notification asked for, as the
  /// phone hands it over; the gate takes it from here.
  final ValueNotifier<QuickAction?>? quick;

  /// Puts the app in the background without closing it: Android's back
  /// on the first screen.
  final Future<void> Function()? leave;

  /// How long the app was away; the phone's clocks unless given.
  final AwayClock? awayClock;

  @override
  State<VaultRoot> createState() => _VaultRootState();
}

class _VaultRootState extends State<VaultRoot> with WidgetsBindingObserver {
  late final _gate = LockGate<AppRoute>(
    widget.startup,
    autoLock: () => widget.preferences.autoLock,
    clock: widget.awayClock,
  );

  /// The one owner of leaving and coming back: the gate first, then the
  /// open ledger's session.
  late final _lifecycle = AppLifecycle(_gate);

  /// The navigator of the session now open; a new one for each.
  var _navigator = GlobalKey<NavigatorState>();

  /// The session that navigator belongs to.
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _generation = _gate.generation;
    _gate.addListener(_follow);
    widget.quick?.addListener(_asked);
    _asked();
    _hideScreen();
  }

  @override
  void dispose() {
    widget.quick?.removeListener(_asked);
    WidgetsBinding.instance.removeObserver(this);
    _gate
      ..removeListener(_follow)
      ..dispose();
    super.dispose();
  }

  /// A session ended or began: every route of the one before goes.
  void _follow() {
    if (_gate.generation != _generation) {
      _generation = _gate.generation;
      _navigator = GlobalKey<NavigatorState>();
      // A note of the session before (it may name an amount) lives above
      // the navigator, in the app's one messenger: it goes too.
      appMessenger.currentState?.clearSnackBars();
      _hideScreen();
    }
    setState(() {});
    // The cover is drawn even though the app has just left the screen
    // and frames have stopped: so the last picture the phone holds of
    // the app is the cover, not the ledger.
    if (_gate.covered) WidgetsBinding.instance.scheduleForcedFrame();
  }

  /// Hands the gate what the phone asked for.
  void _asked() {
    final quick = widget.quick;
    final action = quick?.value;
    if (quick == null || action == null) return;
    quick.value = null;
    _gate.ask(action);
  }

  /// Screenshots are kept off whatever is shown while no ledger is open.
  void _hideScreen() {
    final privacy = widget.privacy;
    if (privacy == null) return;
    privacy.showing(locked: widget.startup.state is! Ready).catchError((
      Object error,
    ) {
      ErrorLog.instance.record(ErrorSteps.screenPrivacy, error);
    });
  }

  /// Leaving and coming back go through [AppLifecycle] only: the gate
  /// covers or locks the ledger before a frame of it is drawn, then the
  /// open ledger's session runs, in that order.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _lifecycle.changed(state);

  @override
  Widget build(BuildContext context) {
    final startup = widget.startup;
    return ExpenseApp(
      preferences: widget.preferences,
      cover: Platform.isAndroid,
      systemHides: Platform.isAndroid ? androidHidesRecents : null,
      navigatorKey: _navigator,
      frame: (context, child) => LockCover(
        covered: _gate.covered,
        child: child ?? const SizedBox.shrink(),
      ),
      home: ListenableBuilder(
        listenable: startup,
        builder: (context, _) => switch (startup.state) {
          Ready(:final vault) => OpenedLedger(
            key: ObjectKey(vault),
            startup: startup,
            vault: vault,
            privacy: widget.privacy,
            preferences: widget.preferences,
            gate: _gate,
            lifecycle: _lifecycle,
            leave: widget.leave,
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
}

/// The app on an unlocked [vault]: it loads the book, then shows it. A
/// ledger just created shows its recovery code first.
class OpenedLedger extends StatefulWidget {
  const OpenedLedger({
    super.key,
    required this.startup,
    required this.vault,
    required this.preferences,
    required this.gate,
    required this.lifecycle,
    this.privacy,
    this.leave,
  });

  final Startup startup;
  final OpenVault vault;
  final ScreenPrivacy? privacy;
  final Preferences preferences;

  /// The lock gate this opening of the ledger sits behind.
  final LockGate<AppRoute> gate;

  /// Tells this opening of the ledger when the app leaves and comes back.
  final AppLifecycle lifecycle;

  /// Puts the app in the background without closing it.
  final Future<void> Function()? leave;

  @override
  State<OpenedLedger> createState() => _OpenedLedgerState();
}

class _OpenedLedgerState extends State<OpenedLedger>
    implements LifecycleSession {
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

  /// Fires at the next local midnight, so a screen left open moves on to
  /// the new day; set again each time it fires and when the app returns.
  Timer? _midnight;

  void _watchMidnight(Ledger ledger) {
    _midnight?.cancel();
    _midnight = Timer(untilNextMidnight(AppClock.now()), () {
      ledger.checkDay();
      if (mounted) _watchMidnight(ledger);
    });
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

  /// How the gate locks this opening: what is being written is kept
  /// first.
  late final Future<void> Function() _lock = _services.backupManager.lock;

  @override
  void initState() {
    super.initState();
    widget.lifecycle.attach(this);
    widget.gate.attach(_lock);
    _ledger.then((ledger) {
      if (mounted) _watchMidnight(ledger);
    }).ignore();
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
    _midnight?.cancel();
    widget.gate.detach(_lock);
    widget.lifecycle.detach(this);
    _services.dispose();
    super.dispose();
  }

  /// Whether this opening of the ledger is still the open one and not
  /// being closed: only then is anything written to it.
  bool get _writable =>
      mounted &&
      !widget.gate.closing &&
      switch (widget.startup.state) {
        Ready(:final vault) => identical(vault, widget.vault),
        _ => false,
      };

  /// Going away leaves the backups (AppLifecycle calls this once a leave).
  @override
  void leave() => unawaited(_services.left());

  /// Back with the ledger still open (the gate decided first): once the
  /// book is open, and only while it stays open, books what fell due
  /// meanwhile and looks for prices and versions again.
  @override
  void returned() {
    _ledger.then((ledger) {
      if (!_writable) return;
      ledger.checkDay();
      _watchMidnight(ledger);
      _tellBooked(_session.bookDue(ledger));
      _services.resumed();
    }).ignore();
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
          // Through the gate: an action reaches the screens only while
          // the ledger is open and in front.
          quick: widget.gate.quick,
          receipts: _services.receipts,
          drive: _services.drive,
          phone: _services.phone,
          market: _services.market,
          update: _services.update,
          // The camera is a trip the app sends the person on.
          scanQr: Platform.isAndroid
              ? ({preparing}) =>
                    Errands.run(() => androidScanQr(preparing: preparing))
              : null,
          onPlace: (page) => widget.gate.place = page,
          takeReturn: widget.gate.takeReturn,
          leave: widget.leave,
        ),
      );
    },
  );
}
