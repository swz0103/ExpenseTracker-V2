import 'dart:convert';

import 'package:expense_tracker/src/features/import/model/invoice_qr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // AB12345678, 113/10/25, random 1234, sales 100 and total 105 in hex,
  // no buyer, seller 12345678, 24 characters of check code: 77 in all.
  const head =
      'AB12345678'
      '1131025'
      '1234'
      '00000064'
      '00000069'
      '00000000'
      '12345678'
      'ABCDEFGHIJKLMNOPQRSTUVWX';

  test('the left code: number, day, total, seller and items', () {
    expect(head.length, 77);
    final invoice = InvoiceQr.parse('$head:**********:2:3:1:乾電池:1:55:口罩:2:25')!;
    expect(invoice.number, 'AB12345678');
    expect(invoice.date, DateTime.utc(2024, 10, 25));
    expect(invoice.total, 105);
    expect(invoice.seller, '12345678');
    expect([for (final i in invoice.items) i.name], ['乾電池', '口罩']);
    expect(invoice.items.last.count, 2);
    expect(invoice.items.last.price, 25);
    expect(invoice.wantsMore, isTrue);
    expect(invoice.note, '乾電池 等 2 項 發票 AB12345678');

    final whole = invoice.withRight('**牛奶:1:35');
    expect([for (final i in whole.items) i.name], ['乾電池', '口罩', '牛奶']);
    expect(whole.wantsMore, isFalse);
    // A left code again is not a right one.
    expect(invoice.withRight(head).items, hasLength(2));
  });

  test('names written in Base64', () {
    final name = base64.encode(utf8.encode('咖啡'));
    final invoice = InvoiceQr.parse('$head:**********:1:1:2:$name:1:105')!;
    expect(invoice.items.single.name, '咖啡');
  });

  test('a code with no items still gives the total', () {
    final invoice = InvoiceQr.parse(head)!;
    expect(invoice.items, isEmpty);
    expect(invoice.wantsMore, isFalse);
    expect(invoice.note, '發票 AB12345678');
  });

  test('anything else is not an invoice', () {
    expect(
      InvoiceQr.parse(
        'https://example.com/a-long-address-that-is-long-enough-to-pass-77-chars-check-x',
      ),
      isNull,
    );
    expect(InvoiceQr.parse('**牛奶:1:35'), isNull);
    // 13 is no month.
    expect(InvoiceQr.parse(head.replaceRange(13, 15, '13')), isNull);
    // No total.
    expect(InvoiceQr.parse(head.replaceRange(29, 37, '00000000')), isNull);
  });
}
