import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:market/market_adapters.dart';
import 'package:market/market_data.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

import 'app.dart';
import '../features/backup/model/drive_backup.dart';
import '../features/backup/model/drive_sync.dart';
import '../features/backup/model/leftovers.dart';
import '../core/ledger/table_journal.dart';
import '../features/backup/model/vault_keeper.dart';
import '../features/reminders/model/calendar_sync.dart';
import '../features/entries/model/receipt_photos.dart';
import '../core/look/widgets.dart';
import '../core/ledger/ledger.dart';
import '../features/reminders/model/notifications.dart';
import '../features/lock/ui/lock_screen.dart';
import '../features/lock/ui/recovery_code.dart';
import 'shell.dart';
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

  DateTime? _leftAt;

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
        )
      : null;
  Ledger? _loaded;
  late final Future<Ledger> _ledger = _open();

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
    unawaited(_quotes(ledger));
    unawaited(_weeklyBackup());
    _calendar?.follow(ledger);
    _notifier?.follow(ledger);
    return ledger;
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

  Future<void> _quotes(Ledger ledger) async {
    try {
      final quotes = await _journal.refreshQuotes([
        for (final h in ledger.holdings)
          if (h.shares > 0) h.code,
      ]);
      final rates = await _journal.refreshRates();
      if ((quotes || rates) && mounted) {
        final market = _journal.market();
        ledger.setMarket(
          holdings: market.holdings,
          moves: market.moves,
          rates: market.rates,
          quotedOn: market.quotedOn,
        );
      }
    } on Object catch (error) {
      // Prices and rates are only informational; the ledger may have
      // locked.
      Perf.instance.problem('收盤價與匯率', error);
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
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Locks the ledger when the app comes back after [_away] or more.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        _leftAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        _ledger.then((ledger) => ledger.checkDay()).ignore();
        final left = _leftAt;
        _leftAt = null;
        if (left != null &&
            !widget.startup.passwordless &&
            DateTime.now().difference(left) >= _away) {
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
        ),
      );
    },
  );
}
