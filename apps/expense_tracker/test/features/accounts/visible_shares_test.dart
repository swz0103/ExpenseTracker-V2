import 'package:expense_tracker/src/features/accounts/ui/accounts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a small sum keeps a visible slice; the rest share by size', () {
    final shares = visibleShares([486631, 786528, 3200, 296829]);
    expect(shares[2], 0.06);
    expect(shares.reduce((a, b) => a + b), closeTo(1, 1e-9));
    expect(shares[1], greaterThan(shares[0]));
    expect(shares[0], greaterThan(shares[3]));
  });

  test('nothing small leaves the plain proportions', () {
    expect(visibleShares([1, 1]), [0.5, 0.5]);
  });
}
