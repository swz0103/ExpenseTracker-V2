import 'package:foundation_values/foundation_values.dart';

import 'csv.dart';

/// One e-invoice from the Ministry of Finance's consumption download
/// (財政部電子發票整合服務平台「消費明細」CSV), its line items added up.
final class EInvoice {
  EInvoice({
    required this.number,
    required this.date,
    required this.seller,
    required this.amount,
    required List<String> items,
  }) : items = List.unmodifiable(items);

  /// Unique per invoice, such as `AB12345678`; use it to skip invoices
  /// already booked.
  final String number;
  final BusinessDate date;
  final String seller;

  /// The invoice total in NT$.
  final Money amount;

  /// Item names in order, each once.
  final List<String> items;
}

/// The invoices in [text], oldest first. Columns are found by their
/// headers, not their order; voided invoices (作廢) are left out. A row
/// that cannot be read stops the import with its line number, so nothing
/// is booked from a half-understood file.
List<EInvoice> parseEInvoices(String text) {
  final rows = readCsv(text);
  if (rows.isEmpty) return const [];
  final header = [for (final name in rows.first) name.trim()];
  int column(String name, {bool required = true}) {
    final index = header.indexOf(name);
    if (index < 0 && required) {
      throw FormatException('Missing column $name');
    }
    return index;
  }

  final dateAt = column('發票日期');
  final numberAt = column('發票號碼');
  final amountAt = column('消費明細_金額');
  final statusAt = column('發票狀態', required: false);
  final sellerAt = column('賣方名稱', required: false);
  final itemAt = column('消費明細_品名', required: false);
  String cell(List<String> row, int index) =>
      index >= 0 && index < row.length ? row[index].trim() : '';

  final invoices = <String, _Invoice>{};
  for (final (i, row) in rows.skip(1).indexed) {
    final line = i + 2;
    final number = cell(row, numberAt);
    if (number.isEmpty) continue;
    final invoice = invoices[number] ??= _Invoice(
      number,
      _date(cell(row, dateAt), line),
      cell(row, sellerAt),
      voided: cell(row, statusAt).contains('作廢'),
    );
    invoice.millionths += _millionths(cell(row, amountAt), line);
    final item = cell(row, itemAt);
    if (item.isNotEmpty && !invoice.items.contains(item)) {
      invoice.items.add(item);
    }
  }
  final twd = Currency.of('TWD');
  final million = BigInt.from(1000000);
  final result = [
    for (final invoice in invoices.values)
      if (!invoice.voided)
        EInvoice(
          number: invoice.number,
          date: invoice.date,
          seller: invoice.seller,
          amount: Money.quantizeRatio(twd, invoice.millionths, million),
          items: invoice.items,
        ),
  ];
  result.sort((a, b) => a.date.compareTo(b.date));
  return result;
}

final class _Invoice {
  _Invoice(this.number, this.date, this.seller, {required this.voided});

  final String number;
  final BusinessDate date;
  final String seller;
  final bool voided;
  final items = <String>[];
  var millionths = BigInt.zero;
}

BusinessDate _date(String text, int line) {
  final match = _yyyymmdd.firstMatch(text);
  if (match != null) {
    try {
      return BusinessDate(
        int.parse(match[1]!),
        int.parse(match[2]!),
        int.parse(match[3]!),
      );
    } on FormatException {
      // Not a calendar date; reported below with the line number.
    }
  }
  throw FormatException('Line $line: invoice date $text');
}

/// A decimal amount in millionths of a dollar, exactly.
BigInt _millionths(String text, int line) {
  final match = _amount.firstMatch(text);
  if (match == null) throw FormatException('Line $line: amount $text');
  final fraction = (match[3] ?? '').padRight(6, '0');
  final value = BigInt.parse('${match[2]}$fraction');
  return match[1] == '-' ? -value : value;
}

final _yyyymmdd = RegExp(r'^(\d{4})(\d{2})(\d{2})$');
final _amount = RegExp(r'^(-?)(\d{1,12})(?:\.(\d{1,6}))?$');
