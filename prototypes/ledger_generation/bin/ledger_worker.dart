import 'dart:io';
import 'dart:convert';

import 'package:foundation_values/foundation_values.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:ledger_generation_probe/safety_backup.dart';
import 'package:storage_generation_probe/generation_store.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';

Future<void> main(List<String> args) async {
  if (args.length != 8 &&
      !(args.length == 9 &&
          [
            'protected',
            'categories',
            'references',
            'tags',
            'merchants',
            'transfers',
            'fxTransfers',
            'refunds',
            'reversals',
            'notes',
          ].contains(args[8])))
    exit(64);
  try {
    final slots = FixtureKeySlots(Directory(args[1]));
    final store = LedgerStore(
      Directory(args[0]),
      slots,
      catalogProtection: args.length == 9
          ? fixtureCatalogProtection(slots)
          : null,
      categoryAware: args.length == 9 && args[8] == 'categories',
      categoryReferences: args.length == 9 && args[8] == 'references',
      tagsAware: args.length == 9 && args[8] == 'tags',
      merchantsAware: args.length == 9 && args[8] == 'merchants',
      transfersAware: args.length == 9 && args[8] == 'transfers',
      refundsAware: args.length == 9 && args[8] == 'refunds',
      reversalsAware: args.length == 9 && args[8] == 'reversals',
      notesAware: args.length == 9 && args[8] == 'notes',
      fxTransfersAware: args.length == 9 && args[8] == 'fxTransfers',
    );
    if (args[5] == 'upgrade') {
      final request = UpgradeRequest.decode(File(args[2]).readAsStringSync());
      final credentials = jsonDecode(File(args[3]).readAsStringSync()) as Map;
      await (store.notesAware
          ? upgradeNotes
          : store.reversalsAware
          ? upgradeReversals
          : store.refundsAware
          ? upgradeRefunds
          : store.fxTransfersAware
          ? upgradeFxTransfers
          : store.transfersAware
          ? upgradeTransfers
          : store.merchantsAware
          ? upgradeMerchants
          : store.tagsAware
          ? upgradeTags
          : store.categoryReferences
          ? upgradeCategoryReferences
          : upgradeCategories)(
        store,
        request,
        Directory(args[4]),
        password: credentials['password'] as String,
        recoveryKey: credentials['recoveryKey'] as String,
        checkpoint: (point) {
          if (point == args[6]) exit(73);
        },
      );
      File(args[7]).writeAsBytesSync(await store.snapshot(), flush: true);
      return;
    }
    final envelope = File(args[2]).readAsStringSync();
    final credential = File(args[3]).readAsStringSync();
    await store.restore(
      envelope,
      OperationId.parse(args[4]),
      password: args[5] == 'password' ? credential : null,
      recoveryKey: args[5] == 'recovery' ? credential : null,
      checkpoint: (point) {
        if (point == args[6]) exit(73);
      },
    );
    File(args[7]).writeAsBytesSync(await store.snapshot(), flush: true);
  } catch (_) {
    stderr.writeln('Ledger worker failed');
    exit(70);
  }
}
