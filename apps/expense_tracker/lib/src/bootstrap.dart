import 'dart:io';

import 'package:backup_security/backup_security.dart';
import 'package:flutter/material.dart';
import 'package:ledger_vault/ledger_vault.dart';

import 'app.dart';
import 'startup.dart';

/// The only production composition (code audit C-01): the encrypted ledger
/// in [directory], opened through [Startup]. The memory preview is not
/// reachable from here; a test walks the imports to keep it that way.
Startup productionStartup(Directory directory, {DeviceUnlock? device}) =>
    Startup(LedgerVault(directory, codec: KeyringCodec()), device: device);

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

/// Follows [startup]: the app once a ledger is unlocked, otherwise the
/// setup and unlock screens, which are rebuilt with the new interface.
class VaultRoot extends StatelessWidget {
  const VaultRoot({super.key, required this.startup});

  final Startup startup;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: startup,
    builder: (context, _) => switch (startup.state) {
      Ready(:final session) => ExpenseApp(session: session),
      NeedsSetup() => const _Waiting('記帳本 V2：尚未建立帳本'),
      Locked() => const _Waiting('記帳本 V2：已鎖定'),
    },
  );
}

class _Waiting extends StatelessWidget {
  const _Waiting(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(body: Center(child: Text(message))),
  );
}
