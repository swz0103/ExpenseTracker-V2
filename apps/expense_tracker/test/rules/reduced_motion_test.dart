import 'package:flutter_test/flutter_test.dart';

import '../support/places.dart';

/// Every place a person reaches opens without a fault with the phone set
/// to reduce motion, when every animation is given no time (Motion.of).
/// Some widgets trip over no time at all, as AnimatedSize did.
void main() {
  testWidgets('every place opens with motion turned off', (tester) async {
    for (final place in allPlaces) {
      await place.open(tester, const Look(360, 1, still: true));
      expect(tester.takeException(), isNull, reason: place.name);
    }
  });
}
