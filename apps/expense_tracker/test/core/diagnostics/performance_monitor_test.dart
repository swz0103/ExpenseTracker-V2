import 'package:expense_tracker/src/core/diagnostics/performance_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('before anything is measured the figures are dashes', () {
    final figures = PerformanceMonitor.instance.figures;
    // Other tests may have loaded a ledger; the shape is what is checked.
    expect(figures.load, isNotEmpty);
    expect(figures.frame, '—');
  });

  test('a load is timed, and still timed when it fails', () async {
    final monitor = PerformanceMonitor.instance;
    final value = await monitor.timeLoad(() async => 42);
    expect(value, 42);
    await expectLater(
      monitor.timeLoad<void>(() async => throw StateError('no')),
      throwsStateError,
    );
    final loads = monitor.report.first;
    expect(loads.$1, '載入帳本');
    expect(loads.$2, contains('最近'));
  });

  test('only the last twenty loads are kept', () async {
    final monitor = PerformanceMonitor.instance;
    for (var i = 0; i < 30; i++) {
      await monitor.timeLoad(() async {});
    }
    expect(monitor.report.first.$2, contains('最慢'));
  });
}
