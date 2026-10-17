import 'dart:async';
import 'dart:io';

import 'package:backup_security/backup_security.dart';
import 'package:flutter/material.dart';
import 'package:ledger_vault/ledger_vault.dart';
import 'package:market_adapters/market_adapters.dart';
import 'package:market_data/market_data.dart';

import 'app.dart';
import 'book/vault_journal.dart';
import 'book/vault_keeper.dart';
import 'model/ledger.dart';
import 'pages/lock_screen.dart';
import 'pages/shell.dart';
import 'platform.dart';
import 'startup.dart';

/// The only production composition (code audit C-01): the encrypted ledger
/// in [directory], opened through [Startup]. The memory preview is not
/// reachable from here; a test walks the imports to keep it that way.
Startup productionStartup(Directory directory, {DeviceUnlock? device}) =>
    Startup(LedgerVault(directory, codec: KeyringCodec()), device: device);

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
  const VaultRoot({super.key, required this.startup});

  final Startup startup;

  @override
  Widget build(BuildContext context) => ExpenseApp(
    home: ListenableBuilder(
      listenable: startup,
      builder: (context, _) => switch (startup.state) {
        Ready(:final vault) => OpenedLedger(
          key: ObjectKey(vault),
          startup: startup,
          vault: vault,
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
  const OpenedLedger({super.key, required this.startup, required this.vault});

  final Startup startup;
  final OpenVault vault;

  @override
  State<OpenedLedger> createState() => _OpenedLedgerState();
}

class _OpenedLedgerState extends State<OpenedLedger>
    with WidgetsBindingObserver {
  /// How long the app may sit in the background before the ledger locks.
  static const _away = Duration(minutes: 5);

  DateTime? _leftAt;

  late final _journal = VaultJournal(
    widget.vault,
    market: MarketDataGateway(transport: const IoMarketTransport()),
  );
  late final _keeper = VaultKeeper(
    widget.startup,
    widget.vault,
    _journal,
    beforeLock: () async => _loaded?.settled,
    export: Platform.isAndroid ? androidExportFile : null,
  );
  Ledger? _loaded;
  late final Future<Ledger> _ledger = _open();

  /// Loads the book, then fetches closing prices and takes the weekly
  /// backup in the background.
  Future<Ledger> _open() async {
    final ledger = await _journal.load();
    _loaded = ledger;
    unawaited(_quotes(ledger));
    unawaited(_keeper.backUpIfDue().catchError((Object _) => null));
    return ledger;
  }

  Future<void> _quotes(Ledger ledger) async {
    try {
      final quotes = await _journal.refreshQuotes();
      final rates = await _journal.refreshRates();
      if ((quotes || rates) && mounted) ledger.refresh();
    } on Object catch (error) {
      // Prices and rates are only informational; the ledger may have
      // locked.
      debugPrint('Closing prices or rates not refreshed: $error');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final code = widget.startup.takeRecoveryCode();
    if (code == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(showRecoveryCode(context, code));
    });
  }

  @override
  void dispose() {
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
        final left = _leftAt;
        _leftAt = null;
        if (left != null && DateTime.now().difference(left) >= _away) {
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
      return AppShell(ledger: ledger, keeper: _keeper);
    },
  );
}
