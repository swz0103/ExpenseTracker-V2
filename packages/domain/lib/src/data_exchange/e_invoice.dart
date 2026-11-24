import 'package:core/foundation_values.dart';

import 'csv.dart';
import 'import_day.dart';

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

/// The invoices in [text] that can be booked, oldest first
/// ([readEInvoices]).
List<EInvoice> parseEInvoices(String text) => readEInvoices(text).invoices;

/// Why an invoice of the file is not booked.
enum InvoiceRefusal {
  /// Its rows disagree on its date or its seller: which is right is not
  /// guessed at.
  rowsDisagree,

  /// Dated before the earliest year an import takes (D93).
  tooEarly,
}

/// An invoice of the file left out, the [line] it starts on, and why.
typedef RefusedInvoice = ({String number, int line, InvoiceRefusal why});

/// What a ministry file holds: the [invoices] to book, oldest first, and
/// those left out with why ([refused]), in the order they come.
typedef EInvoiceFile = ({
  List<EInvoice> invoices,
  List<RefusedInvoice> refused,
});

/// The invoices of the ministry's file [text]. Columns are found by
/// their headers, not their order. The rows of one invoice number are one
/// invoice: a row voided (作廢) voids it, whichever row says so; rows that
/// disagree on its date or seller leave it out, refused, as does a date
/// before [earliestImportYear]. A row that cannot be read stops the
/// import with its line number (as the file counts its lines), so nothing
/// is booked from a half-understood file.
EInvoiceFile readEInvoices(String text) {
  final rows = readCsvRecords(text);
  if (rows.isEmpty) return (invoices: const [], refused: const []);
  final header = [for (final name in rows.first.cells) name.trim()];
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
  for (final (:line, cells: row) in rows.skip(1)) {
    final number = cell(row, numberAt);
    if (number.isEmpty) continue;
    final dateText = cell(row, dateAt);
    final day = _date(dateText, line);
    final seller = cell(row, sellerAt);
    final invoice = invoices[number] ??= _Invoice(
      number,
      line,
      day,
      dateText,
      seller,
    );
    if (cell(row, statusAt).contains('作廢')) invoice.voided = true;
    if (dateText != invoice.dateText || seller != invoice.seller) {
      invoice.disagrees = true;
    }
    invoice.millionths += _millionths(cell(row, amountAt), line);
    final item = cell(row, itemAt);
    if (item.isNotEmpty && !invoice.items.contains(item)) {
      invoice.items.add(item);
    }
  }
  final twd = Currency.of('TWD');
  final million = BigInt.from(1000000);
  final refused = <RefusedInvoice>[];
  final result = <EInvoice>[];
  for (final invoice in invoices.values) {
    if (invoice.voided) continue;
    final day = invoice.day;
    if (invoice.disagrees || day is! DayRead) {
      refused.add((
        number: invoice.number,
        line: invoice.line,
        why: invoice.disagrees
            ? InvoiceRefusal.rowsDisagree
            : InvoiceRefusal.tooEarly,
      ));
      continue;
    }
    result.add(
      EInvoice(
        number: invoice.number,
        date: day.date,
        seller: invoice.seller,
        amount: Money.quantizeRatio(twd, invoice.millionths, million),
        items: invoice.items,
      ),
    );
  }
  result.sort((a, b) => a.date.compareTo(b.date));
  return (invoices: result, refused: refused);
}

final class _Invoice {
  _Invoice(this.number, this.line, this.day, this.dateText, this.seller);

  final String number;

  /// The line of its first row.
  final int line;
  final ImportDay day;

  /// Its date as its first row writes it.
  final String dateText;
  final String seller;
  var voided = false;

  /// Its rows disagree on its date or its seller.
  var disagrees = false;
  final items = <String>[];
  var millionths = BigInt.zero;
}

/// The day of an invoice, its date written as the ministry writes it
/// (20261003), read by the import's one rule ([readImportDay]). Any other
/// form, or no date of the calendar, stops the file at [line]; a date too
/// early leaves the invoice out.
ImportDay _date(String text, int line) {
  if (_yyyymmdd.hasMatch(text)) {
    final day = readImportDay(text);
    if (day case DayRead() || DayRefused(problem: DayProblem.tooEarly)) {
      return day;
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

final _yyyymmdd = RegExp(r'^\d{8}$');
final _amount = RegExp(r'^(-?)(\d{1,12})(?:\.(\d{1,6}))?$');
