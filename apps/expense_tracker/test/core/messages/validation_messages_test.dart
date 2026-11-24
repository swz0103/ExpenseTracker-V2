import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/messages/validation_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('R12: too many shares is told as such', () {
    expect(validationMessage(const SharesTooLarge(maxShares)), '股數超過可記錄的上限');
  });
}
