import 'dart:async';
import 'dart:io';

import 'package:backup_security/backup_security.dart';
import 'package:flutter/material.dart';
import 'package:ledger_vault/ledger_vault.dart';
import 'package:market_adapters/market_adapters.dart';
import 'package:market_data/market_data.dart';

import 'app.dart';
import 'book/looks.dart';
import 'book/vault_journal.dart';
import 'book/vault_keeper.dart';
import 'demo/ledger.dart';
import 'pages/lock_screen.dart';
import 'pages/shell.dart';
import 'startup.dart';

/// The only production composition (code audit C-01): the encrypted ledger
/// in [directory], opened through [Startup]. The memory preview is not
/// reachable from here; a test walks the imports to keep it that way.
Startup productionStartup(Directory directory, {DeviceUnlock? device}) =>
    Startup(
      LedgerVault(directory, codec: KeyringCodec(), modules: [looksSchema]),
      device: device,
    );

/// Where this device keeps the ledger. Android's private app directory
/// comes with the platform wiring (STATUS 4b-2); until then only desktop
/// development builds can start.
Directory applicationDirectory() {
  final home = Platform.isWindows
      ? Platform.environment['APPDATA']
      : Platform.environment['HOME'];
  if (Platform.isAndroid || Platform.isIOS || home == null) {
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

class _OpenedLedgerState extends State<OpenedLedger> {
  late final _journal = VaultJournal(
    widget.vault,
    market: MarketDataGateway(transport: const IoMarketTransport()),
  );
  late final Future<Ledger> _ledger = _open();

  /// Loads the book, then fetches closing prices in the background.
  Future<Ledger> _open() async {
    final ledger = await _journal.load();
    unawaited(_quotes(ledger));
    return ledger;
  }

  Future<void> _quotes(Ledger ledger) async {
    if (await _journal.refreshQuotes() && mounted) ledger.refresh();
  }

  @override
  void initState() {
    super.initState();
    final code = widget.startup.takeRecoveryCode();
    if (code == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(showRecoveryCode(context, code));
    });
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
        keeper: VaultKeeper(widget.startup, widget.vault, _journal),
      );
    },
  );
}
