import 'dart:io';

import 'package:expense_tracker/src/app/lifecycle_services.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:expense_tracker/src/core/platform/away_clock.dart';
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
/// coming back, and the lock after a while away.
void main() {
  late Directory directory;
  late Startup startup;
  late OpenVault vault;
  late List<String> said;
  late _Offline offline;
  var running = Duration.zero;

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
    running = Duration.zero;
  });

  tearDown(() => directory.deleteSync(recursive: true));

  LifecycleServices services() => LifecycleServices(
    startup: startup,
    vault: vault,
    preferences: Preferences(),
    say: said.add,
    offerUpdate: (_) async => fail('nothing to offer off Android'),
    transport: offline,
    awayClock: AwayClock(running: () => running),
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
    await s.paused();
    await s.resumed();
    await pumpEventQueue();
    // Asked at most every 20 minutes (MarketFeed's gap).
    expect(offline.asked, first);
    s.dispose();
  });

  test('back within five minutes the ledger stays open', () async {
    final s = services();
    await s.start(await s.dataSource.load());
    await s.paused();
    running = const Duration(minutes: 4);
    expect(await s.resumed(), isFalse);
    expect(startup.state, isA<Ready>());
    s.dispose();
  });

  test('back after five minutes or more the ledger locks', () async {
    final s = services();
    await s.start(await s.dataSource.load());
    await s.paused();
    running = LifecycleServices.away;
    expect(await s.resumed(), isTrue);
    expect(startup.state, isNot(isA<Ready>()));
    s.dispose();
  });

  test('leaving before the ledger is open does nothing', () async {
    final s = services();
    await s.paused();
    expect(await s.resumed(), isFalse);
    s.dispose();
  });
}
