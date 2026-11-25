import 'package:ledger_entries/model.dart';
import 'package:test/test.dart';

void main() {
  test('the model entry point gathers the entry and the account kinds', () {
    expect(EntryType.values, hasLength(6));
    expect(AccountKind.card.isDebt, isTrue);
    expect(homeCode, 'TWD');
    expect(transferCategory, '轉帳');
  });

  test('D80: a transfer with no category is kept under 轉帳; the rest as '
      'they are', () {
    expect(keptCategory(EntryType.transfer, ''), '轉帳');
    expect(keptCategory(EntryType.transfer, ' '), '轉帳');
    expect(keptCategory(EntryType.transfer, '還款'), '還款');
    expect(keptCategory(EntryType.expense, ''), '');
  });
}
