import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:market/market_adapters.dart';
import 'package:market/market_data.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

import 'android/background_backup_adapter.dart';
import 'android/home_widget_adapter.dart';
import 'android/market_cache_adapter.dart';
import 'android/update_adapter.dart';
import 'platform.dart';
import '../core/diagnostics/error_log.dart';
import '../core/diagnostics/error_steps.dart';
import '../core/ledger/ledger.dart';
import '../core/ledger/persistence/sql_ledger_data_source.dart';
import '../core/ledger/persistence/upgrade_backup.dart';
import '../core/time/app_clock.dart';
import '../core/platform/distribution.dart';
import '../core/platform/one_at_a_time.dart';
import '../core/platform/preferences.dart';
import '../core/platform/startup.dart';
import '../core/messages/update_messages.dart';
import '../features/backup/model/drive_backup.dart';
import '../features/backup/model/drive_sync.dart';
import '../features/backup/model/encrypted_backup_manager.dart';
import '../features/backup/model/file_cleanup.dart';
import '../features/backup/model/outbox.dart';
import '../features/investments/model/price_months.dart';
import '../features/backup/model/phone_backup.dart';
import '../features/entries/model/receipt_photos.dart';
import '../features/investments/model/market_feed.dart';
import '../features/overview/model/home_widget.dart';
import '../features/overview/ui/overview.dart' show widgetBookOf;
import '../features/reminders/model/calendar_sync.dart';
import '../features/reminders/model/reminder_alerts.dart';
import '../features/reminders/ui/reminders_section.dart' show reminderBookOf;
import '../features/settings/model/app_update.dart';

/// What runs beside an open ledger for as long as the app is: closing
/// prices, the calendar, notifications and the home-screen widget follow
/// it; backups are taken and left for the background job; newer versions
/// are looked for. Most of it is Android's; elsewhere only the ledger's
/// own backups and prices run. Locking after a while away is not here:
/// the lock gate decides it (core/platform/lock_gate.dart).
///
/// The screens are reached only through [say] and [offerUpdate], so a
/// test can run it without them.
final class LifecycleServices {
  LifecycleServices({
    required this.startup,
    required this.vault,
    required this.preferences,
    required this.say,
    required this.offerUpdate,
    this.android = false,
    MarketTransport? transport,
  }) : _transport = transport ?? const IoMarketTransport();

  /// Where closing prices and rates are asked for: the network, or a fake
  /// in tests.
  final MarketTransport _transport;

  final Startup startup;
  final OpenVault vault;
  final Preferences preferences;

  /// Whether the phone's own services are there to use.
  final bool android;

  /// Tells the person something, briefly.
  final void Function(String note) say;

  /// Offers a newer version found.
  final Future<void> Function(AppUpdate update) offerUpdate;

  Directory get _directory => startup.directory;

  /// On Android, the day lists the background job keeps (`MarketWorker`),
  /// read before the network.
  late final _marketCache = android
      ? CachedMarketTransport(
          _transport,
          Directory('${_directory.path}/market'),
        )
      : null;

  /// Where the book is kept, with the market's gateway.
  late final dataSource = SqlLedgerDataSource(
    vault.store,
    clock: AppClock.clock,
    market: MarketDataGateway(
      transport: _marketCache ?? _transport,
      // The exchanges' snapshots are a few MiB of JSON.
      decodeJson: (body) => Isolate.run(() => jsonDecode(body)),
    ),
    // A book an earlier version kept is copied before it is brought up,
    // and not brought up while the copy cannot be kept (D19).
    beforeUpgrade: () => keepUpgradeBackup(backupManager.keepBeforeUpgrade),
    keepsJournal: true,
  )..onJournalDamaged = startup.journalDamaged;

  Ledger? _ledger;

  late final backupManager = EncryptedBackupManager(
    startup,
    vault,
    beforeLock: () async => _ledger?.settled,
    export: android ? androidExportFile : null,
    pick: android ? androidPickFile : null,
  );

  /// The phone's calendar for due dates.
  late final calendar = android
      ? CalendarSync(const AndroidCalendar(), _directory)
      : null;

  /// The phone's notifications.
  late final notifier = android
      ? Notifier(const AndroidNotifications(), preferences)
      : null;

  /// Backups on Google Drive.
  late final drive = android
      ? DriveSync(
          androidDrive(),
          preferences,
          withBackup: backupManager.withBackup<void>,
          revision: () => backupManager.revision,
          ledger: backupManager.ledgerId,
          epoch: () => backupManager.backupEpoch,
          unmetered: androidUnmetered,
        )
      : null;

  /// Backups to a folder on the phone.
  late final phone = android
      ? PhoneBackup(
          const AndroidFolder(),
          preferences,
          withBackup: backupManager.withBackup<void>,
          revision: () => backupManager.revision,
          ledger: backupManager.ledgerId,
        )
      : null;

  /// Backups left on leaving the app, delivered by a background job.
  late final _outbox = android
      ? Outbox(
          _directory,
          preferences,
          write: backupManager.writeInto,
          revision: () => backupManager.revision,
          ledger: backupManager.ledgerId,
          schedule: androidBackgroundBackups,
        )
      : null;

  /// The figures the home-screen widget 本月概況 shows.
  late final _homeWidget = android
      ? HomeWidget(
          File('${_directory.path}/widget.json'),
          preferences,
          refresh: androidRefreshWidgets,
        )
      : null;

  /// Closing prices and rates, once started.
  MarketFeed? get market => _market;
  MarketFeed? _market;

  /// Newer versions of the app, once started on Android.
  AppUpdate? get update => _update;
  AppUpdate? _update;

  /// The phone's receipt photos, sealed with the ledger's key.
  ReceiptPhotos? get receipts => _receipts;
  ReceiptPhotos? _receipts;

  /// Starts everything that follows [ledger]. The weekly backup and the
  /// look for a newer version go on after this returns.
  Future<void> start(Ledger ledger) async {
    _ledger = ledger;
    if (android) {
      // Photos no entry keeps any more: replaced, taken away, or taken
      // for an entry never saved. Done before a photo can be taken, so
      // none is swept as it is saved.
      try {
        await sweepReceipts(_directory, ledger.attachmentCommands.receiptFiles);
      } on Object catch (error) {
        ErrorLog.instance.record('清除收據照片', error);
      }
      _receipts = AndroidReceipts(
        _directory,
        await FileBox.derive(vault.keys, FileBox.receipts),
      );
    }
    // The chart's months, sealed with the ledger's key; one another key
    // sealed (a restore, a reset) or plain from an older version goes.
    final box = await FileBox.derive(vault.keys, FileBox.prices);
    final prices = PriceMonths(_directory, seal: box.seal, open: box.open);
    unawaited(prices.settle());
    final market = _market = MarketFeed(
      dataSource,
      changes: ledger,
      holdings: ledger.holdings,
      commands: ledger.holdingCommands,
      today: () => ledger.today,
      kept: prices,
    );
    _beside(market.refresh());
    _beside(_followMarket());
    _beside(weeklyBackup());
    if (android && canSelfUpdate) {
      try {
        _update = AppUpdate(
          const AndroidUpdatePort(),
          preferences,
          cache: await androidCacheDirectory(),
        );
        _beside(checkUpdate());
      } on Object catch (error) {
        ErrorLog.instance.record(UpdateMessages.checkStep, error);
      }
    }
    calendar?.follow(reminderBookOf(ledger));
    notifier?.follow(reminderBookOf(ledger));
    _homeWidget?.follow(widgetBookOf(ledger));
  }

  /// What [start] and [resumed] left running (the weekly backup, the
  /// prices, the look for a newer version, the phone's folder): done when
  /// all of it is. Each records its own failures; one it let through
  /// fails this too.
  Future<void> get settled async {
    while (_running.isNotEmpty) {
      final now = List.of(_running);
      _running.clear();
      await Future.wait(now);
    }
  }

  final _running = <Future<void>>[];

  /// Runs [work] beside the app, without waiting for it, kept for
  /// [settled].
  void _beside(Future<void> work) {
    _running.add(work);
    unawaited(work);
  }

  /// What the market's background job fetches while the app is closed:
  /// the exchanges' lists while shares are held, the bank's rates while an
  /// account is kept in another currency (AND-05).
  static ({bool stocks, bool rates}) marketWanted(Ledger ledger) => (
    stocks: ledger.holdings.all.any((h) => h.shares > 0),
    rates: ledger.accounts.all.any((a) => a.foreign),
  );

  /// Tells the market's background job what the ledger needs now, and
  /// stops it when it needs nothing. Done at start and on each leave.
  Future<void> _followMarket() async {
    final cache = _marketCache;
    final ledger = _ledger;
    if (cache == null || ledger == null) return;
    final wanted = marketWanted(ledger);
    try {
      final any = await cache.writeList(
        stocks: wanted.stocks,
        rates: wanted.rates,
      );
      await androidMarketJob(on: any);
    } on Object catch (error) {
      ErrorLog.instance.record(ErrorSteps.marketCache, error);
    }
  }

  /// The app was left (AppLifecycle calls this once a leave): the copy
  /// for Android's own backup is kept and the backup left for the
  /// background job. One at a time: a leave while these run starts them
  /// once more after, not beside them, so two never write at once and
  /// the change made in between is still kept. Done when the last is.
  Future<void> left() => _leaving.run();

  late final _leaving = OneAtATime(_prepareOutbox);

  /// The app came back and the ledger stays open: prices and versions are
  /// looked for again, and what the background job did is noted.
  void resumed() {
    _market?.refresh().ignore();
    _beside(checkUpdate());
    if (_ledger != null) {
      collectOutbox();
      _beside(phoneBackup());
    }
  }

  /// Takes the weekly backup, then sends one to Google Drive when linked;
  /// a failure is said, not kept quiet. Drive out of reach is tried again
  /// at the next start.
  Future<void> weeklyBackup() async {
    try {
      await backupManager.backUpIfDue();
    } on Object catch (error) {
      ErrorLog.instance.record('每週備份', error);
      say('每週自動備份沒有完成，可以到「設定」手動備份');
    }
    collectOutbox();
    await phoneBackup();
    final drive = this.drive;
    if (drive == null) return;
    try {
      await drive.backUpIfDue();
    } on DriveException catch (error) {
      ErrorLog.instance.record('雲端硬碟備份', error);
      if (error.problem != DriveProblem.offline) {
        say('沒有備份到 Google 雲端硬碟，可以到「設定」重新連結');
      }
    } on Object catch (error) {
      ErrorLog.instance.record('雲端硬碟備份', error);
    }
  }

  /// Writes the backup to the phone's folder when one is due. A failure
  /// is said once a run, not at each return to the app; the settings page
  /// keeps showing it.
  Future<void> phoneBackup() async {
    final phone = this.phone;
    if (phone == null || await phone.backUpIfDue()) return;
    final problem = phone.problem;
    if (problem == null || _phoneWarned) return;
    _phoneWarned = true;
    ErrorLog.instance.record('手機資料夾備份', problem);
    say('沒有備份到手機資料夾，可以到「設定」重新選擇');
  }

  var _phoneWarned = false;

  /// Looks for a newer version, and offers it at once, with what it
  /// changes; offered once a run, after which it waits in 設定 › 關於.
  Future<void> checkUpdate() async {
    final update = _update;
    final newer = await update?.checkIfDue();
    if (update == null || newer == null) return;
    if (_offered == newer.build || !update.mayOffer(newer)) return;
    _offered = newer.build;
    await offerUpdate(update);
  }

  /// The build last offered this run.
  int? _offered;

  /// When the app is left with changes not in a backup yet, keeps the copy
  /// Android takes to the person's Google account by itself, and leaves
  /// the backup for the background job, so it reaches the phone's folder
  /// and Drive without the app being opened again.
  Future<void> _prepareOutbox() async {
    final ledger = _ledger;
    if (ledger == null) return;
    await _followMarket();
    try {
      await ledger.settled;
      // Android's own backup takes this copy, so a new phone can restore
      // the ledger from the welcome page.
      if (android) await backupManager.keepCloudCopy();
    } on Object catch (error) {
      ErrorLog.instance.record('Google 備份', error);
    }
    final outbox = _outbox;
    if (outbox == null) return;
    try {
      await outbox.prepare();
    } on Object catch (error) {
      ErrorLog.instance.record('背景備份', error);
    }
  }

  /// After a reset of the keys: the backup waiting for the background
  /// job was sealed with the old ones, and goes ([Outbox.empty]).
  Future<void> emptyOutbox() async {
    try {
      await _outbox?.empty();
    } on Object catch (error) {
      ErrorLog.instance.record(ErrorSteps.outboxEmpty, error);
    }
  }

  /// Notes what the background job delivered while the app was closed.
  void collectOutbox() {
    try {
      for (final problem in _outbox?.collect() ?? const <String>[]) {
        ErrorLog.instance.record('背景備份', problem);
      }
    } on Object catch (error) {
      ErrorLog.instance.record('背景備份', error);
    }
  }

  void dispose() {
    calendar?.stop();
    notifier?.stop();
    _homeWidget?.stop();
    drive?.dispose();
    phone?.dispose();
    _market?.dispose();
    _update?.dispose();
  }
}
