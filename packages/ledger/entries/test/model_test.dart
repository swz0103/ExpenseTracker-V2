import 'package:ledger_entries/model.dart';
import 'package:test/test.dart';

void main() {
  test('the model entry point gathers the entry and the account kinds', () {
    expect(EntryType.values, hasLength(6));
    expect(AccountKind.card.isDebt, isTrue);
    expect(homeCode, 'TWD');
    expect(transferCategory, '轉帳');
  });
}
