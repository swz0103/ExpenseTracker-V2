import 'dart:convert';

/// One item on a paper e-invoice: its name, how many, and the unit price.
typedef InvoiceItem = ({String name, double count, double price});

/// The left QR code of a Taiwanese paper e-invoice (電子發票證明聯), as
/// the Ministry of Finance lays it out: 77 fixed characters (number, date,
/// random code, amounts in hexadecimal, buyer's and seller's tax ids,
/// check code), then, after a colon, the seller's own 10 characters, how
/// many items this code carries, how many there are, how the names are
/// written, and name:count:price for each. Items that do not fit go on in
/// the right code, which starts with `**`.
final class InvoiceQr {
  const InvoiceQr({
    required this.number,
    required this.date,
    required this.total,
    required this.seller,
    required this.items,
    required this.itemCount,
    required this.encoding,
  });

  /// Such as AB12345678.
  final String number;

  /// Midnight UTC of the day it was issued.
  final DateTime date;

  /// What was paid, tax included, in whole NT$.
  final int total;

  /// The seller's tax id (統一編號).
  final String seller;
  final List<InvoiceItem> items;

  /// How many items the invoice has in all, both codes together.
  final int itemCount;

  /// How the names are written: 0 Big5, 1 UTF-8, 2 Base64.
  final int encoding;

  /// Whether the right code still has items to read.
  bool get wantsMore => items.length < itemCount;

  /// This invoice with the items of its right [code] added; itself when
  /// [code] is not a right code.
  InvoiceQr withRight(String code) {
    if (!code.startsWith('**')) return this;
    return InvoiceQr(
      number: number,
      date: date,
      total: total,
      seller: seller,
      items: [
        ...items,
        ..._items(
          code.substring(2).replaceFirst(RegExp('^:'), '').split(':'),
          encoding,
        ),
      ],
      itemCount: itemCount,
      encoding: encoding,
    );
  }

  /// Reads a left code; null for anything else (a right code, a web
  /// address, one too short or with a date or amount that cannot be).
  static InvoiceQr? parse(String code) {
    if (code.length < 77) return null;
    final number = code.substring(0, 10);
    if (!RegExp(r'^[A-Z]{2}\d{8}$').hasMatch(number)) return null;
    final rocYear = int.tryParse(code.substring(10, 13));
    final month = int.tryParse(code.substring(13, 15));
    final day = int.tryParse(code.substring(15, 17));
    if (rocYear == null || month == null || day == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime.utc(rocYear + 1911, month, day);
    if (date.month != month) return null;
    final total = int.tryParse(code.substring(29, 37), radix: 16);
    if (total == null || total <= 0) return null;
    final seller = code.substring(45, 53);
    if (!RegExp(r'^\d{8}$').hasMatch(seller)) return null;
    // After the 77: [''], own use, items here, items in all, encoding,
    // then name, count, price for each.
    final rest = code.substring(77).split(':');
    var itemCount = 0;
    var encoding = 1;
    var items = const <InvoiceItem>[];
    if (rest.length >= 5) {
      itemCount = int.tryParse(rest[3]) ?? 0;
      encoding = int.tryParse(rest[4]) ?? 1;
      items = _items(rest.sublist(5), encoding);
    }
    return InvoiceQr(
      number: number,
      date: date,
      total: total,
      seller: seller,
      items: items,
      itemCount: itemCount < items.length ? items.length : itemCount,
      encoding: encoding,
    );
  }

  /// name:count:price, again and again; a broken last one is dropped.
  static List<InvoiceItem> _items(List<String> cells, int encoding) => [
    for (var i = 0; i + 2 < cells.length; i += 3)
      if (_name(cells[i], encoding) case final name when name.isNotEmpty)
        (
          name: name,
          count: double.tryParse(cells[i + 1]) ?? 1,
          price: double.tryParse(cells[i + 2]) ?? 0,
        ),
  ];

  static String _name(String raw, int encoding) {
    final text = raw.trim();
    if (encoding != 2) return text;
    try {
      return utf8.decode(base64.decode(text), allowMalformed: true).trim();
    } on FormatException {
      return text;
    }
  }

  /// 「乾電池 等 3 項 發票 AB12345678」, as an imported invoice's note.
  String get note {
    final what = items.isEmpty ? '' : items.first.name;
    final more = items.length > 1 ? ' 等 ${items.length} 項' : '';
    return '$what$more 發票 $number'.trim();
  }
}
