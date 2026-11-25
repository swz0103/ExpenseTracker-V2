import 'package:core/foundation_values.dart';
import 'package:core/money/typed_text.dart' show plainText;

import 'cells.dart' show AmountCell;
import 'csv.dart';
import 'import_day.dart';

/// One e-invoice of a Ministry of Finance download: the consumption CSV
/// (財政部電子發票整合服務平台「消費明細」), its line items added up, or
/// a carrier's M line with its D lines.
final class EInvoice {
  EInvoice({
    required this.number,
    required this.date,
    required this.seller,
    required this.amount,
    required List<String> items,
    this.line = 1,
  }) : items = List.unmodifiable(items);

  /// Unique per invoice, such as `AB12345678`; use it to skip invoices
  /// already booked.
  final String number;
  final BusinessDate date;
  final String seller;

  /// The invoice total in NT$.
  final Money amount;

  /// Item names in order: each once in the CSV, as the D lines list them.
  final List<String> items;

  /// The line of the file it starts on.
  final int line;
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

  /// Its date is no date of the calendar (M lines).
  unreadableDay,

  /// Its year has one or two digits (D93; M lines).
  shortYear,

  /// Dated after the last day an entry may be (M lines).
  tooLate,

  /// Its total is not an amount above zero (M lines).
  badAmount,

  /// Voided (作廢; M lines: the CSV leaves a voided invoice out unnamed).
  voided,

  /// Its number came earlier in the file (M lines).
  repeated,
}

/// An invoice of the file left out, the [line] it starts on, and why;
/// [seller] names it where the file gives it no number.
typedef RefusedInvoice = ({
  String number,
  String seller,
  int line,
  InvoiceRefusal why,
});

/// What a ministry file holds: the [invoices] to book, oldest first, and
/// those left out with why ([refused]), in the order they come.
typedef EInvoiceFile = ({
  List<EInvoice> invoices,
  List<RefusedInvoice> refused,
});

/// The invoices of a ministry file [text] of either kind: the
/// consumption CSV, which has a 發票號碼 column ([readEInvoices]), or a
/// carrier's M and D lines ([readInvoiceLines], [latest] the last day an
/// invoice may be dated). The one reader of e-invoice files.
EInvoiceFile readInvoiceFile(String text, {BusinessDate? latest}) =>
    text.contains(_numberColumn)
    ? readEInvoices(text)
    : readInvoiceLines(text, latest: latest);

/// The invoices of a carrier's M lines (載具名稱|載具號碼|日期|統編|店名|
/// 發票號碼|總金額|狀態), each with the items of its D lines
/// (D|發票號碼|金額|品名), oldest first. Each M line is read on its own:
/// one that cannot be read, is voided, or repeats a number already read
/// is left out, named, and the rest are read. Its day is read by the
/// import's one rule ([readImportDay]); [latest] is the last it may be.
EInvoiceFile readInvoiceLines(String text, {BusinessDate? latest}) {
  final items = <String, List<String>>{};
  final heads = <(int, List<String>)>[];
  for (final (i, raw) in text.split('\n').indexed) {
    final cells = [for (final c in raw.trim().split('|')) plainText(c).trim()];
    if (cells.first == 'M' && cells.length >= 8) heads.add((i + 1, cells));
    if (cells.first == 'D' && cells.length >= 4) {
      (items[cells[1]] ??= []).add(cells[3]);
    }
  }
  final twd = Currency.of('TWD');
  final invoices = <EInvoice>[];
  final refused = <RefusedInvoice>[];
  final numbers = <String>{};
  for (final (line, cells) in heads) {
    final day = readImportDay(cells[3], latest: latest);
    final seller = cells[5];
    final number = cells[6];
    final total = const AmountCell().read(cells[7], twd.code).minorOrNull;
    final why = switch (day) {
      DayRefused(:final problem) => _dayRefusal(problem),
      _ when total == null || total <= 0 => InvoiceRefusal.badAmount,
      _ when cells.length > 8 && cells[8].contains(_void) =>
        InvoiceRefusal.voided,
      _ when number.isNotEmpty && numbers.contains(number) =>
        InvoiceRefusal.repeated,
      _ => null,
    };
    if (why != null) {
      refused.add((number: number, seller: seller, line: line, why: why));
      continue;
    }
    if (day case DayRead(:final date) when total != null) {
      numbers.add(number);
      invoices.add(
        EInvoice(
          number: number,
          date: date,
          seller: seller,
          amount: Money(twd, BigInt.from(total)),
          items: items[number] ?? const [],
          line: line,
        ),
      );
    }
  }
  return (invoices: _oldestFirst(invoices), refused: refused);
}

/// [invoices] oldest first, those of one day in the order they came.
List<EInvoice> _oldestFirst(List<EInvoice> invoices) {
  final placed = [...invoices.indexed]
    ..sort((a, b) {
      final byDay = a.$2.date.compareTo(b.$2.date);
      return byDay != 0 ? byDay : a.$1.compareTo(b.$1);
    });
  return [for (final (_, invoice) in placed) invoice];
}

InvoiceRefusal _dayRefusal(DayProblem problem) => switch (problem) {
  DayProblem.unreadable => InvoiceRefusal.unreadableDay,
  DayProblem.shortYear => InvoiceRefusal.shortYear,
  DayProblem.tooEarly => InvoiceRefusal.tooEarly,
  DayProblem.tooLate => InvoiceRefusal.tooLate,
};

const _numberColumn = '發票號碼';
const _void = '作廢';

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
  final header = [for (final name in rows.first.cells) plainText(name).trim()];
  int column(String name, {bool required = true}) {
    final index = header.indexOf(name);
    if (index < 0 && required) {
      throw FormatException('Missing column $name');
    }
    return index;
  }

  final dateAt = column('發票日期');
  final numberAt = column(_numberColumn);
  final amountAt = column('消費明細_金額');
  final statusAt = column('發票狀態', required: false);
  final sellerAt = column('賣方名稱', required: false);
  final itemAt = column('消費明細_品名', required: false);
  String cell(List<String> row, int index) =>
      index >= 0 && index < row.length ? plainText(row[index]).trim() : '';

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
    if (cell(row, statusAt).contains(_void)) invoice.voided = true;
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
        seller: invoice.seller,
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
        line: invoice.line,
      ),
    );
  }
  return (invoices: _oldestFirst(result), refused: refused);
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
