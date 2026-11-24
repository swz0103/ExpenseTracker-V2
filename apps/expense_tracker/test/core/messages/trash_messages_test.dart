import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/messages/trash_messages.dart';
import 'package:expense_tracker/src/core/messages/validation_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('D78: removing an account says what of the trash goes with it', () {
    expect(trashedNamingNote(0), isNull);
    expect(trashedNamingNote(3), '「最近刪除」裡還有 3 筆用到它的紀錄，會一併永久清除，無法再放回。');
  });

  test('D78: an edit of an entry deleted meanwhile is refused in words', () {
    expect(validationMessage(const EntryDeleted()), '這筆已刪除，可到「最近刪除」救回');
  });
}
