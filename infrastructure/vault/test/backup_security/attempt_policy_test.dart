import 'package:test/test.dart';
import 'package:vault/backup_security.dart';

void main() {
  const policy = AttemptPolicy.standard;

  test('the first four wrong tries cost no wait', () {
    for (final failures in [0, 1, 2, 3, 4]) {
      expect(policy.waitAfter(failures), Duration.zero, reason: '$failures');
    }
  });

  test('from the fifth on each wrong try waits longer, an hour at most', () {
    expect(policy.waitAfter(5), const Duration(seconds: 30));
    expect(policy.waitAfter(6), const Duration(minutes: 1));
    expect(policy.waitAfter(7), const Duration(minutes: 2));
    expect(policy.waitAfter(8), const Duration(minutes: 5));
    expect(policy.waitAfter(9), const Duration(minutes: 15));
    expect(policy.waitAfter(10), const Duration(minutes: 30));
    expect(policy.waitAfter(11), const Duration(hours: 1));
    expect(policy.waitAfter(12), const Duration(hours: 1));
    expect(policy.waitAfter(500), const Duration(hours: 1));
  });

  test('a table of its own is read the same way', () {
    const short = AttemptPolicy([
      AttemptStep(failures: 2, wait: Duration(seconds: 3)),
      AttemptStep(failures: 4, wait: Duration(seconds: 9)),
    ]);
    expect(short.waitAfter(1), Duration.zero);
    expect(short.waitAfter(2), const Duration(seconds: 3));
    // No row of its own: the one before it still holds.
    expect(short.waitAfter(3), const Duration(seconds: 3));
    expect(short.waitAfter(4), const Duration(seconds: 9));
  });

  test('no table means no wait', () {
    expect(const AttemptPolicy([]).waitAfter(99), Duration.zero);
  });
}
