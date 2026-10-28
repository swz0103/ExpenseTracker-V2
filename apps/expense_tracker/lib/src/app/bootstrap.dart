import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:market/market_adapters.dart';
import 'package:market/market_data.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

import 'android/backups.dart';
import 'app.dart';
import '../features/backup/model/drive_backup.dart';
import '../features/backup/model/drive_sync.dart';
import '../features/backup/model/leftovers.dart';
import '../features/backup/model/outbox.dart';
import '../features/backup/model/phone_backup.dart';
import '../core/ledger/table_journal.dart';
import '../features/investments/model/market_feed.dart';
import '../features/backup/model/vault_keeper.dart';
import '../features/reminders/model/calendar_sync.dart';
import '../features/entries/model/receipt_photos.dart';
import '../core/look/widgets.dart';
import '../core/ledger/ledger.dart';
import '../features/reminders/model/inbox_apply.dart';
import '../features/reminders/model/notifications.dart';
import '../features/lock/model/restore_sources.dart';
import '../features/lock/ui/lock_screen.dart';
import '../features/lock/ui/recovery_code.dart';
import 'shell.dart';
import '../core/away_clock.dart';
import '../core/perf.dart';
import 'platform.dart';
import '../core/preferences.dart';
import '../core/screen_privacy.dart';
import '../features/settings/model/services.dart';
import '../features/lock/model/startup.dart';

/// The only production composition (code audit C-01): the encrypted ledger
/// in [directory], opened through [Startup]. The memory preview is not
/// reachable from here; a test walks the imports to keep it that way.
Startup productionStartup(Directory directory, {DeviceUnlock? device}) =>
    Startup(
      LedgerVault(directory, codec: KeyringCodec(minimumPassword: 6)),
      device: device,
      check: TableJournal.check,
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
  /// How long the app may sit in the background before the ledger locks.
  static const _away = Duration(minutes: 5);

  /// How long the app was away, by a clock that cannot be set back.
  final _awayClock = AwayClock();

  late final _journal = TableJournal(
    widget.vault.store,
    market: MarketDataGateway(
      transport: const IoMarketTransport(),
      // The exchanges' snapshots are a few MiB of JSON.
      decodeJson: (body) => Isolate.run(() => jsonDecode(body)),
    ),
  );

  /// The phone's calendar for due dates, on Android.
  late final _calendar = Platform.isAndroid
      ? CalendarSync(const AndroidCalendar(), widget.startup.directory)
      : null;

  /// The phone's notifications, on Android.
  late final _notifier = Platform.isAndroid
      ? Notifier(const AndroidNotifications(), widget.preferences)
      : null;

  late final _keeper = VaultKeeper(
    widget.startup,
    widget.vault,
    beforeLock: () async => _loaded?.settled,
    export: Platform.isAndroid ? androidExportFile : null,
    pick: Platform.isAndroid ? androidPickFile : null,
  );

  /// Backups on Google Drive, on Android.
  late final _drive = Platform.isAndroid
      ? DriveSync(
          androidDrive(),
          widget.preferences,
          withBackup: _keeper.withBackup<void>,
          revision: () => _keeper.revision,
          ledger: _keeper.ledgerId,
          unmetered: androidUnmetered,
        )
      : null;

  /// Backups to a folder on the phone, on Android.
  late final _phone = Platform.isAndroid
      ? PhoneBackup(
          const AndroidFolder(),
          widget.preferences,
          withBackup: _keeper.withBackup<void>,
          revision: () => _keeper.revision,
          ledger: _keeper.ledgerId,
        )
      : null;

  /// Backups left on leaving the app, delivered by a background job, on
  /// Android.
  late final _outbox = Platform.isAndroid
      ? Outbox(
          widget.startup.directory,
          widget.preferences,
          write: _keeper.writeInto,
          revision: () => _keeper.revision,
          ledger: _keeper.ledgerId,
          schedule: androidBackgroundBackups,
        )
      : null;
  Ledger? _loaded;
  late final Future<Ledger> _ledger = _open();

  /// Closing prices and rates, once the book is loaded.
  MarketFeed? _market;

  /// The phone's receipt photos, sealed with the ledger's key.
  ReceiptPhotos? _receipts;

  /// Loads the book, then fetches closing prices and takes the weekly
  /// backup in the background.
  Future<Ledger> _open() async {
    final ledger = await _journal.load();
    _loaded = ledger;
    if (Platform.isAndroid) {
      // Photos no entry keeps any more: replaced, taken away, or taken
      // for an entry never saved.
      // Done before a photo can be taken, so none is swept as it is saved.
      try {
        await sweepReceipts(widget.startup.directory, ledger.receiptFiles);
      } on Object catch (error) {
        Perf.instance.problem('清除收據照片', error);
      }
      _receipts = AndroidReceipts(
        widget.startup.directory,
        await FileBox.derive(widget.vault.keys, 'receipts'),
      );
    }
    await _readInbox(ledger);
    _bookDue(ledger);
    final market = _market = MarketFeed(_journal, ledger);
    unawaited(market.refresh());
    unawaited(_weeklyBackup());
    _calendar?.follow(ledger);
    _notifier?.follow(ledger);
    return ledger;
  }

  /// Applies what was written into the ledger's inbox while it was
  /// locked (「確認入帳」 on notifications), then empties it; what could
  /// not be booked is listed once. Opening the inbox also writes its
  /// public key, which the notifications seal with.
  Future<void> _readInbox(Ledger ledger) async {
    final InboxOutcome outcome;
    try {
      final inbox = await LedgerInbox.open(
        widget.startup.directory,
        widget.vault.keys,
      );
      final items = await inbox.read();
      if (items.isEmpty) return;
      outcome = applyInbox(ledger, items);
      for (final item in items) {
        await inbox.remove(item.name);
      }
    } on Object catch (error) {
      Perf.instance.problem('收件匣', error);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (outcome.booked > 0) {
        showNote(context, '已依通知上的確認記下 ${outcome.booked} 筆');
      }
      if (outcome.review.isEmpty) return;
      unawaited(
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('通知上的確認'),
            content: Text(outcome.review.join('\n')),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('知道了'),
              ),
            ],
          ),
        ),
      );
    });
  }

  /// Books the recurring items marked to book themselves whose day has
  /// come, and says how many.
  void _bookDue(Ledger ledger) {
    final int booked;
    try {
      booked = ledger.bookDue();
    } on Object catch (error) {
      Perf.instance.problem('定期自動入帳', error);
      return;
    }
    if (booked == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showNote(context, '已自動記下 $booked 筆定期交易');
    });
  }

  /// Writes the backup to the phone's folder when one is due. A failure
  /// is said once a run, not at each return to the app; the settings page
  /// keeps showing it.
  Future<void> _phoneBackup() async {
    final phone = _phone;
    if (phone == null || await phone.backUpIfDue()) return;
    final problem = phone.problem;
    if (problem == null || _phoneWarned) return;
    _phoneWarned = true;
    Perf.instance.problem('手機資料夾備份', problem);
    if (mounted) showNote(context, '沒有備份到手機資料夾，可以到「設定」重新選擇');
  }

  var _phoneWarned = false;

  /// Leaves the backup for the background job when the app is left with
  /// changes not in one yet, so it reaches the phone's folder and Drive
  /// without the app being opened again.
  Future<void> _prepareOutbox() async {
    final outbox = _outbox;
    final ledger = _loaded;
    if (outbox == null || ledger == null) return;
    try {
      await ledger.settled;
      await outbox.prepare();
    } on Object catch (error) {
      Perf.instance.problem('背景備份', error);
    }
  }

  /// Notes what the background job delivered while the app was closed.
  void _collectOutbox() {
    try {
      for (final problem in _outbox?.collect() ?? const <String>[]) {
        Perf.instance.problem('背景備份', problem);
      }
    } on Object catch (error) {
      Perf.instance.problem('背景備份', error);
    }
  }

  /// Takes the weekly backup, then sends one to Google Drive when linked;
  /// a failure is said, not kept quiet. Drive out of reach is tried again
  /// at the next start.
  Future<void> _weeklyBackup() async {
    try {
      await _keeper.backUpIfDue();
    } on Object catch (error) {
      Perf.instance.problem('每週備份', error);
      if (mounted) showNote(context, '每週自動備份沒有完成，可以到「設定」手動備份');
    }
    _collectOutbox();
    await _phoneBackup();
    final drive = _drive;
    if (drive == null) return;
    try {
      await drive.backUpIfDue();
    } on DriveException catch (error) {
      Perf.instance.problem('雲端硬碟備份', error);
      if (error.problem != DriveProblem.offline && mounted) {
        showNote(context, '沒有備份到 Google 雲端硬碟，可以到「設定」重新連結');
      }
    } on Object catch (error) {
      Perf.instance.problem('雲端硬碟備份', error);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final code = widget.startup.takeRecoveryCode();
    final recovered = widget.startup.takeRecoveryNotice();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (code != null) unawaited(showRecoveryCode(context, code));
      if (recovered) {
        unawaited(
          showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('已用救援碼打開'),
              content: const Text('現在打開 App 不需要密碼。想要密碼的話，可以到「設定」重新設定。'),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('知道了'),
                ),
              ],
            ),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _calendar?.stop();
    _notifier?.stop();
    _drive?.dispose();
    _phone?.dispose();
    _market?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Locks the ledger when the app comes back after [_away] or more.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        _awayClock.leave();
        unawaited(_prepareOutbox());
      case AppLifecycleState.resumed:
        _ledger.then((ledger) {
          ledger.checkDay();
          _bookDue(ledger);
        }).ignore();
        _market?.refresh().ignore();
        if (_loaded != null) {
          _collectOutbox();
          unawaited(_phoneBackup());
        }
        if (_awayClock.back(_away) && !widget.startup.passwordless) {
          unawaited(_keeper.lock());
        }
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
        return Scaffold(body: Center(child: Text('無法讀取帳本：${snapshot.error}')));
      }
      if (ledger == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return AppShell(
        ledger: ledger,
        services: Services(
          keeper: _keeper,
          calendar: _calendar,
          privacy: widget.privacy,
          preferences: widget.preferences,
          notifier: _notifier,
          quick: Platform.isAndroid ? quickAction : null,
          receipts: _receipts,
          drive: _drive,
          phone: _phone,
          market: _market,
        ),
      );
    },
  );
}
