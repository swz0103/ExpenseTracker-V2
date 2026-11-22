import 'package:domain/investments.dart';
import 'package:test/test.dart';

void main() {
  test('a stock with shares left is held', () {
    expect(holdingStatus(1), HoldingStatus.held);
    expect(holdingStatus(1000), HoldingStatus.held);
  });

  test('a stock sold to the last share is sold out', () {
    expect(holdingStatus(0), HoldingStatus.soldOut);
  });
}
