import 'package:core/money/typed_text.dart';
import 'package:test/test.dart';

void main() {
  test('full-width forms read as ASCII; the rest stays', () {
    expect(halfWidth('１２．５'), '12.5');
    expect(halfWidth('６折'), '6折');
    expect(halfWidth('－３，０００'), '-3,000');
    expect(halfWidth('　７　'), ' 7 ');
    expect(halfWidth('六折 0.6'), '六折 0.6');
    expect(halfWidth(''), '');
  });
}
