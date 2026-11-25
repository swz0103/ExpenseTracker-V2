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
import 'quarantine_notices.dart';
import 'quiet_failures.dart';
import 'upgrade_held_page.dart';
import '../features/backup/model/encrypted_backup_manager.dart';
import '../features/backup/model/hand_over.dart';
import '../features/backup/model/old_key_backups.dart';
import '../features/backup/model/outbox.dart';
import '../features/backup/ui/old_key_backups_offer.dart';
import '../core/ledger/persistence/quarantine.dart';
import '../core/design_system/design_system.dart';
import '../core/diagnostics/error_log.dart';
import '../core/messages/loading_messages.dart';
import '../features/backup/ui/backup_section.dart' show restoreFromBackup;
import '../core/ledger/ledger.dart';
import '../features/recurring/ui/held_bookings.dart';
import '../features/reminders/model/inbox_apply.dart';
import '../features/backup/model/restore_sources.dart';
import '../features/lock/ui/lock_screen.dart';
import '../features/lock/ui/views/new_password_view.dart';
import '../core/messages/key_messages.dart';
import '../core/diagnostics/error_steps.dart';
import '../core/design_system/dialogs.dart';
import '../core/design_system/feedback.dart';
import '../core/platform/app_lifecycle.dart';
import '../core/platform/away_clock.dart';
import '../core/platform/errands.dart';
import '../core/navigation/nav.dart' show AppRoute;
import '../core/platform/lock_gate.dart';
import '../core/platform/quick_action.dart';
import '../core/widgets/diagnostics_export.dart';
import '../core/widgets/lock_cover.dart';
import '../core/design_system/recovery_code.dart';
import 'shell.dart';
import 'platform.dart';
import '../core/platform/preferences.dart';
import '../core/platform/screen_privacy.dart';
import '../features/settings/ui/update_panel.dart';
import '../features/settings/model/platform_services.dart';
import '../core/platform/startup.dart';
import '../core/platform/startup_state.dart';
import '../core/time/app_clock.dart';

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

  /// What the services keep for the run (review 31); notes said while open.
  late final _run = ServicesRun(
    QuietFailures(
      (note) async => widget.startup.state is Ready && await queueNote(note),
      book: () => widget.startup.bookChanges,
    ),
  );

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
      _run.quiet.dropWaiting();
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

  /// What a restore goes on from above: every revision a backup of
  /// this phone's ledger is known delivered or waiting at (review 28).
  int _deliveredRevision() =>
      Outbox.deliveredRevision(widget.startup.directory, widget.preferences);

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
            run: _run,
            leave: widget.leave,
          ),
          Damaged() => DamagedBookPage.of(startup),
          final state => LockScreen(
            key: ValueKey(state.runtimeType),
            startup: startup,
            sources: Platform.isAndroid
                ? RestoreSources(
                    pickFile: androidPickFile,
                    drive: androidDrive,
                    cacheDirectory: androidCacheDirectory,
                    deliveredRevision: _deliveredRevision,
                  )
                : RestoreSources(deliveredRevision: _deliveredRevision),
            diagnostics: Platform.isAndroid
                ? textHandOver(startup.directory, androidExportFile)
                : null,
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
    required this.run,
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

  /// What the services remember for the whole run of the app.
  final ServicesRun run;

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
    run: widget.run,
  );

  /// Opening the book: load, inbox, health check, what is due.
  late final _session = LedgerSession(
    load: _services.dataSource.load,
    bringUp: _services.dataSource.bringUp,
    quarantined: () => _services.dataSource.quarantined,
    failed: (step) => _services.quiet.failed(step),
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

  /// Holds the opening while the copy before an upgrade cannot be kept
  /// (D19); its page shows meanwhile.
  late final _hold = UpgradeHold()
    ..addListener(() {
      if (mounted) setState(() {});
    });

  Future<Ledger> _open() async {
    final start = await widget.startup.readingBook(
      _hold.prepare(_session.prepare).then((_) => _session.open()),
    );
    await _services.start(start.ledger);
    // Rows set aside are told (D18): newer ones once a set, others always.
    final tell = await QuarantineNotices(widget.startup.folder.quarantineTold)
        .toTell(start.quarantined);
    _afterFrame(() {
      if (start.inbox case final inbox?) _tellInbox(inbox);
      _tellBooked(start.ledger, start.booked, start.held);
      if (tell.isNotEmpty) {
        unawaited(_tellQuarantined(tell, all: start.quarantined));
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
  }) => exportDiagnostics(
    context,
    _services.backupManager.exportFile,
    rows: rows,
    failure: failure,
  );

  /// Tells how many rows were set aside ([rows]), with a way to report
  /// them (every row set aside, [all]), to restore a backup, or to go on
  /// with the rest of the book.
  Future<void> _tellQuarantined(
    List<QuarantinedRow> rows, {
    required List<QuarantinedRow> all,
  }) async {
    final restore = await showQuarantineNotice(
      context,
      rows,
      onExport: () => unawaited(_exportReport(rows: all)),
    );
    if (restore && mounted) {
      await restoreFromBackup(context, _services.backupManager);
    }
  }

  /// From a book that could not be opened, to the lock screen's restore:
  /// a copy of this ledger is kept first when it can be, and the restore
  /// is offered all the same when it cannot.
  Future<void> _restoreAfterFailure() async {
    try {
      // Exception to undo rule: no book opened; the lock screen asks.
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

  /// What the automatic booking did and left, told once (D61).
  late final _held = HeldBookings(notice: _notice);
  void _tellBooked(Ledger l, int booked, List<HeldBooking> held) =>
      unawaited(_held.tell(context, l.recurringCommands, booked, held));

  Future<void> _notice(String title, String text) => tell(context, title, text);

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
              ? _afterReset(code)
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

  /// After a reset of the keys: the backup waiting for the background job
  /// goes (the app's own queue), then the new recovery code, then the
  /// backups and kept databases still sealed with the old keys, offered
  /// to be taken away (D15): on Drive, on the phone, in the folder chosen
  /// for backups (those written before the reset) and the damaged or
  /// old-format copies beside the ledger.
  Future<void> _afterReset(String code) async {
    final resetAt = widget.startup.keysResetAt;
    await _services.emptyOutbox();
    if (!mounted) return;
    await showRecoveryCode(context, code, why: KeyWords.resetDone);
    final drive = _services.drive;
    final phone = _services.phone;
    final backups = _services.backupManager;
    final old = OldKeyBackups(
      epoch: backups.backupEpoch,
      localBackups: backups.keptBackups,
      driveFiles: drive != null && drive.linked ? drive.backups : null,
      trashOnDrive: drive?.trash,
      folderBackups: phone != null && phone.on && resetAt != null
          ? () => phone.writtenBefore(
              resetAt,
              epoch: backups.backupEpoch,
              head: EncryptedBackupManager.head,
            )
          : null,
      deleteInFolder: phone?.remove,
      keptDatabases: backups.keptDatabases,
      deleteDatabase: backups.deleteKeptDatabase,
    );
    if (mounted) await offerToRemoveOldKeyBackups(context, old);
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
  /// book is open, and only while it stays open, applies what was
  /// confirmed on a notification, books what fell due meanwhile and looks
  /// for prices and versions again.
  @override
  void returned() {
    _ledger.then((ledger) async {
      if (!_writable) return;
      ledger.checkDay();
      _watchMidnight(ledger);
      final back = await _session.resume(ledger);
      if (back.inbox case final inbox? when mounted) _tellInbox(inbox);
      if (mounted) _tellBooked(ledger, back.booked, back.held);
      if (_writable) _services.resumed();
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
      if (_hold.held case final held? when ledger == null) {
        return UpgradeHeldPage(
          failure: held,
          onRetry: () => _hold.choose(withoutBackup: false),
          onExport: () => _exportReport(failure: held.error),
          onWithoutBackup: () => _hold.choose(withoutBackup: true),
        );
      }
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
