import 'package:expense_tracker/src/core/away_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const limit = Duration(minutes: 5);
  late DateTime now;
  late Duration running;
  AwayClock clock() => AwayClock(now: () => now, running: () => running);

  setUp(() {
    now = DateTime(2026, 10, 27, 12);
    running = Duration.zero;
  });

  test('a short absence keeps the ledger open, a long one locks it', () {
    final away = clock()..leave();
    now = now.add(const Duration(minutes: 2));
    running += const Duration(minutes: 2);
    expect(away.back(limit), isFalse);
    away.leave();
    now = now.add(const Duration(minutes: 6));
    running += const Duration(minutes: 6);
    expect(away.back(limit), isTrue);
  });

  test("setting the phone's time back does not keep it open", () {
    final away = clock()..leave();
    now = now.subtract(const Duration(hours: 1));
    running += const Duration(minutes: 1);
    expect(away.back(limit), isTrue);
  });

  test('time that only runs forward counts even with the clock held', () {
    final away = clock()..leave();
    running += const Duration(minutes: 10);
    expect(away.back(limit), isTrue);
  });

  test('back without leaving is not away', () {
    expect(clock().back(limit), isFalse);
  });
}
