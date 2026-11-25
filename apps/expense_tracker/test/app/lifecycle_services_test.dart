import 'dart:io';

import 'package:expense_tracker/src/app/lifecycle_services.dart';
import 'package:expense_tracker/src/app/quiet_failures.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
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

  /// The services each test made: what they left running (the weekly
  /// backup above all, which writes into the folder) is waited for before
  /// the folder goes.
  final made = <LifecycleServices>[];

  tearDown(() async {
    for (final s in made) {
      await s.settled;
    }
    made.clear();
    directory.deleteSync(recursive: true);
  });

  /// What the app remembers for its whole run: its notes are said into
  /// [said], each read at once.
  ServicesRun aRun() => ServicesRun(
    QuietFailures((note) async {
      said.add(note);
      return true;
    }),
  );

  LifecycleServices services({ServicesRun? run}) {
    final s = LifecycleServices(
      startup: startup,
      vault: vault,
      preferences: Preferences(),
      say: said.add,
      offerUpdate: (_) async => fail('nothing to offer off Android'),
      run: run ?? aRun(),
      transport: offline,
    );
    made.add(s);
    return s;
  }

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

  test('review 31: what is told once a run stays told across openings of '
      'the ledger, and a backup that failed on leaving is told after the '
      'unlock that follows', () async {
    final run = aRun();
    final first = services(run: run);
    // A backup left on leaving failed, and the app locked while away.
    run.backupFailed = true;
    first.dispose();
    // The next opening has new services, and the same run.
    final second = services(run: run);
    second.collectOutbox();
    await pumpEventQueue();
    expect(said, ['背景備份沒有完成，可在診斷匯出詳細資料']);
    expect(run.backupFailed, isFalse);
    // Told once a run: a third opening, failing again, says nothing.
    run.backupFailed = true;
    services(run: run).collectOutbox();
    await pumpEventQueue();
    expect(said, hasLength(1));
    second.dispose();
  });

  test('settled waits for the weekly backup start left running', () async {
    final s = services();
    await s.start(await s.dataSource.load());
    await s.settled;
    // The first backup of a new ledger is due at once: written by now.
    expect(await s.backupManager.keptBackups(), hasLength(1));
    expect(said, isEmpty);
    // Nothing left: a second wait returns at once.
    await s.settled;
    s.dispose();
  });

  test('what each return to the app starts leaves nothing kept once it '
      'ends (review 27)', () async {
    final s = services();
    await s.start(await s.dataSource.load());
    await s.settled;
    expect(s.running, 0);
    for (var i = 0; i < 5; i++) {
      s.resumed();
    }
    // Each return: the look for a newer version and the phone's folder.
    expect(s.running, 10);
    await s.settled;
    expect(s.running, 0);
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

  test('the market\'s background job fetches only what the ledger needs '
      '(AND-05)', () {
    Ledger book({List<Holding> holdings = const [], String currency = 'TWD'}) =>
        Ledger(
          today: DateTime.utc(2026, 11, 23),
          accounts: [
            Account('a', '帳戶', AccountKind.bank, 0, currency: currency),
          ],
          categories: const [],
          entries: const [],
          holdings: holdings,
          budgets: const [],
          recurring: const [],
        );
    const held = Holding(
      '2330',
      '台積電',
      shares: 1000,
      price: 1000,
      cost: 500000,
      change: 0,
    );
    const soldOut = Holding(
      '0050',
      '元大台灣50',
      shares: 0,
      price: 150,
      cost: 0,
      change: 0,
    );
    expect(LifecycleServices.marketWanted(book()), (
      stocks: false,
      rates: false,
    ));
    expect(LifecycleServices.marketWanted(book(holdings: [soldOut])), (
      stocks: false,
      rates: false,
    ));
    expect(LifecycleServices.marketWanted(book(holdings: [held])), (
      stocks: true,
      rates: false,
    ));
    expect(LifecycleServices.marketWanted(book(currency: 'USD')), (
      stocks: false,
      rates: true,
    ));
  });

  test('leaving before the ledger is open does nothing', () async {
    final s = services();
    await s.left();
    s.resumed();
    expect(startup.state, isA<Ready>());
    s.dispose();
  });
}
