import 'package:expense_tracker/src/core/platform/sync_job.dart';
import 'package:expense_tracker/src/core/ledger/trading.dart';
import 'package:expense_tracker/src/core/navigation/nav.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fails on demand, and says what it was asked to say.
final class _Probe extends SyncJob {
  _Probe(DateTime Function() clock)
    : super('測試', gap: const Duration(minutes: 20), clock: clock);

  var runs = 0;
  String? says;
  var fails = false;

  @override
  Future<void> refresh({bool force = false}) => attempt(force: force, () async {
    runs++;
    if (fails) throw StateError('offline');
    return says;
  });
}

void main() {
  test('a connector waits its gap unless asked outright', () async {
    var now = DateTime.utc(2026, 10, 27, 9);
    final probe = _Probe(() => now);
    addTearDown(probe.dispose);
    await probe.refresh();
    await probe.refresh();
    expect(probe.runs, 1);
    await probe.refresh(force: true);
    expect(probe.runs, 2);
    now = now.add(const Duration(minutes: 21));
    await probe.refresh();
    expect(probe.runs, 3);
    expect(probe.lastSuccess, now);
    expect(probe.problem, isNull);
  });

  test(
    'a failure is shown, not kept quiet, and cleared by a success',
    () async {
      final probe = _Probe(DateTime.now);
      addTearDown(probe.dispose);
      probe.fails = true;
      await probe.refresh(force: true);
      expect(probe.problem, isNotNull);
      expect(probe.lastSuccess, isNull);
      probe
        ..fails = false
        ..says = '0050X 抓不到收盤價';
      await probe.refresh(force: true);
      expect(probe.problem, '0050X 抓不到收盤價');
      probe.says = null;
      await probe.refresh(force: true);
      expect(probe.problem, isNull);
    },
  );

  test('codes are tidied the way the exchanges write them', () {
    expect(tidyCode(' 2330.tw '), '2330');
    expect(tidyCode('00679b.TWO'), '00679B');
    expect(tidyCode('0 0 5 0'), '0050');
    for (final code in ['2330', '0050', '00679B', '6488', '006208']) {
      expect(quotable(code), isTrue, reason: code);
    }
    for (final code in ['台積電', 'AAPL', '123', '0123']) {
      expect(quotable(code), isFalse, reason: code);
    }
  });

  test('places compare by what they show, and know where back leads', () {
    expect(AppRoutes.account('a'), AppRoutes.account('a'));
    expect(AppRoutes.account('a'), isNot(AppRoutes.account('b')));
    expect(AppRoutes.holding('2330').parent, AppRoutes.investments);
    expect(AppRoutes.account('a').parent, isNull);
    expect(AppRoutes.reports, const SectionRoute(MoreDestination.reports));
  });
}
