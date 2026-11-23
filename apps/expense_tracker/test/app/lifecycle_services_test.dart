import 'dart:io';

import 'package:expense_tracker/src/app/lifecycle_services.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/core/platform/startup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market/market_data.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

/// The exchanges out of reach: every ask answers 503.
final class _Offline implements MarketTransport {
  var asked = 0;

  @override
  Future<MarketResponse> get(Uri uri) async {
    asked++;
    return const MarketResponse(503, '');
  }
}

/// What runs beside an open ledger, on a real encrypted ledger in a
/// folder of its own, off Android: prices, the weekly backup, leaving and
/// coming back. Locking after a while away is the lock gate's
/// (test/core/platform/lock_gate_test.dart).
void main() {
  late Directory directory;
  late Startup startup;
  late OpenVault vault;
  late List<String> said;
  late _Offline offline;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('lifecycle-');
    startup = Startup(
      LedgerVault(
        directory,
        codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
      ),
      check: SqlLedgerDataSource.check,
    );
    await startup.setUp('correct horse battery');
    vault = switch (startup.state) {
      Ready(:final vault) => vault,
      _ => throw StateError('not open'),
    };
    said = [];
    offline = _Offline();
  });

  tearDown(() => directory.deleteSync(recursive: true));

  LifecycleServices services() => LifecycleServices(
    startup: startup,
    vault: vault,
    preferences: Preferences(),
    say: said.add,
    offerUpdate: (_) async => fail('nothing to offer off Android'),
    transport: offline,
  );

  test('off Android only the ledger\'s own services run', () async {
    final s = services();
    final ledger = await s.dataSource.load();
    await s.start(ledger);
    expect(s.market, isNotNull);
    expect([
      s.calendar,
      s.notifier,
      s.drive,
      s.phone,
      s.update,
      s.receipts,
    ], everyElement(isNull));
    await s.weeklyBackup();
    expect(said, isEmpty, reason: 'the weekly backup went through');
    s.dispose();
  });

  test('closing prices are asked for on start, not again on coming back '
      'right away', () async {
    final s = services();
    await s.start(await s.dataSource.load());
    await pumpEventQueue();
    final first = offline.asked;
    expect(first, greaterThan(0), reason: 'rates are always asked for');
    await s.left();
    s.resumed();
    await pumpEventQueue();
    // Asked at most every 20 minutes (MarketFeed's gap).
    expect(offline.asked, first);
    s.dispose();
  });

  test(
    'coming back never locks the ledger here: that is the gate\'s',
    () async {
      final s = services();
      await s.start(await s.dataSource.load());
      await s.left();
      s.resumed();
      await pumpEventQueue();
      expect(startup.state, isA<Ready>());
      s.dispose();
    },
  );

  test('leaving before the ledger is open does nothing', () async {
    final s = services();
    await s.left();
    s.resumed();
    expect(startup.state, isA<Ready>());
    s.dispose();
  });
}
