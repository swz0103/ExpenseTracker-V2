import 'package:core/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  test('banking days skip weekends and holidays, T+2 counts open days', () {
    final calendar = BankingCalendar(
      holidays: {BusinessDate(2026, 10, 9)},
      workdays: {BusinessDate(2026, 10, 17)},
    );
    expect(calendar.isOpen(BusinessDate(2026, 10, 8)), isTrue);
    expect(calendar.isOpen(BusinessDate(2026, 10, 9)), isFalse);
    expect(calendar.isOpen(BusinessDate(2026, 10, 10)), isFalse);
    expect(calendar.isOpen(BusinessDate(2026, 10, 17)), isTrue);
    final saturday = BusinessDate(2026, 10, 10);
    expect(calendar.onOrAfter(saturday), BusinessDate(2026, 10, 12));
    // Thursday + 2 skips the holiday Friday and the weekend.
    final thursday = BusinessDate(2026, 10, 8);
    expect(calendar.addOpenDays(thursday, 2), BusinessDate(2026, 10, 13));
    expect(calendar.addOpenDays(thursday, 0), thursday);
    // A make-up Saturday counts.
    final friday = BusinessDate(2026, 10, 16);
    expect(calendar.addOpenDays(friday, 1), BusinessDate(2026, 10, 17));
    expect(() => calendar.addOpenDays(thursday, -1), throwsArgumentError);
  });
}
