import 'package:flutter_test/flutter_test.dart';

import 'android_text_scale.dart';

void main() {
  const scaler = AndroidTextScaler200();

  test("each size in Android's table scales as the table says", () {
    final table = {8.0: 16.0, 14.0: 26.0, 18.0: 30.0, 30.0: 38.0, 100.0: 100.0};
    for (final MapEntry(key: sp, value: dp) in table.entries) {
      expect(scaler.scale(sp), dp, reason: '$sp sp');
    }
  });

  test('between the sizes of the table it is read along a line', () {
    expect(scaler.scale(13), 25); // halfway from 12 (24) to 14 (26)
    expect(scaler.scale(16), 28); // halfway from 14 (26) to 18 (30)
  });

  test('small text is twice as large, very large text as it is', () {
    expect(scaler.scale(6), 12);
    expect(scaler.scale(120), 120);
  });
}
