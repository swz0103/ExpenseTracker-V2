import 'package:expense_tracker/src/core/ledger/repositories/receipt_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an entry with no photo has none', () {
    expect(ReceiptRepository().of('e1'), isNull);
  });

  test('a photo set is told as a change, the same one again is not', () {
    final receipts = ReceiptRepository();
    expect(receipts.set('e1', 'a.jpg'), isTrue);
    expect(receipts.set('e1', 'a.jpg'), isFalse);
    expect(receipts.of('e1'), 'a.jpg');
    expect(receipts.set('e1', 'b.jpg'), isTrue);
    expect(receipts.of('e1'), 'b.jpg');
  });

  test('a photo taken away is gone; taking away none changes nothing', () {
    final receipts = ReceiptRepository({'e1': 'a.jpg'});
    expect(receipts.set('e1', null), isTrue);
    expect(receipts.of('e1'), isNull);
    expect(receipts.files, isEmpty);
    expect(receipts.set('e1', null), isFalse);
  });

  test('every photo kept is listed', () {
    final receipts = ReceiptRepository({'e1': 'a.jpg', 'e2': 'b.jpg'});
    expect(receipts.files.toSet(), {'a.jpg', 'b.jpg'});
  });

  test('the map given is copied, not kept', () {
    final given = {'e1': 'a.jpg'};
    final receipts = ReceiptRepository(given);
    given['e1'] = 'x.jpg';
    expect(receipts.of('e1'), 'a.jpg');
  });

  test('another read anew is taken whole', () {
    final receipts = ReceiptRepository({'e1': 'a.jpg'});
    receipts.replaceWith(ReceiptRepository({'e2': 'b.jpg'}));
    expect(receipts.of('e1'), isNull);
    expect(receipts.of('e2'), 'b.jpg');
  });
}
