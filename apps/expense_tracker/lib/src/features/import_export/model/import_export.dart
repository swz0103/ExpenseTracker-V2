// Exception to shared words: a CSV's columns and kinds are a file
// format; they keep their spelling whatever the screens come to say.
import 'package:core/constants/category_colors.dart';
import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:core/money/amount_parser.dart'
    show AmountOk, AmountProblem, AmountRefused;
import 'package:core/money/typed_text.dart' show plainText;
import 'package:domain/data_exchange.dart';
import 'package:flutter/foundation.dart' show compute, visibleForTesting;

import '../../../core/formatting/words.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/messages/amount_messages.dart';
import '../../../core/messages/import_messages.dart';
import '../../../core/messages/validation_messages.dart';
import '../../entries/model/invoices.dart';

part 'import_reader.dart';

/// The parts of the book an import reads: what is there already, to
/// leave out what it holds and to add what it lacks, and new ids
/// (docs/adr/0013-models-take-what-they-use.md).
final class ImportBook {
  ImportBook({
    required this.accounts,
    required this.categories,
    required this.entries,
    required this.entryQueryService,
    required this.entryValidator,
    required this.marketData,
    required this.recurring,
    required this.inTrash,
    required this.groupInTrash,
    required this.today,
    required this._newId,
  });

  /// The book's today: a day read later than an entry may be dated on it
  /// is refused (r13 F6).
  final DateTime today;

  final AccountReader accounts;
  final CategoryReader categories;
  final EntryReader entries;
  final EntryQueryService entryQueryService;
  final EntryValidator entryValidator;
  final MarketDataReader marketData;

  /// The recurring items an entry read may book.
  final RecurringReader recurring;

  /// Whether an entry of the id given was deleted lately: that id is not given to
  /// an entry read, so putting it back never meets another of that id.
  final bool Function(String id) inTrash;

  /// Whether an entry deleted lately was of the group given: that group
  /// is not given to an entry read, so putting it back never joins it.
  final bool Function(String group) groupInTrash;
  final String Function() _newId;

  Account account(String id) => accounts.resolve(id);

  String newId() => _newId();
}

/// What an import found: the entries to add, the accounts and categories
/// they name that the book does not have yet, and the lines left out, as
/// already in the book or unusable.
final class Import {
  const Import(
    this.entries,
    this.skipped, {
    this.accounts = const [],
    this.categories = const [],
    this.problems = const [],
  });

  final List<Entry> entries;
  final int skipped;
  final List<Account> accounts;
  final List<Category> categories;

  /// Why each line was left out, such as 「第 3 行：日期看不懂」, as
  /// 略過 N 行 lists them.
  final List<String> problems;

  /// This import with only the entries at [kept] (their places in
  /// [entries]), and only the new accounts and categories those use.
  Import only(Set<int> kept) {
    final chosen = [
      for (final (i, e) in entries.indexed)
        if (kept.contains(i)) e,
    ];
    final accountsUsed = {
      for (final e in chosen) ...[e.account, ?e.to],
    };
    final categoriesUsed = {
      for (final e in chosen) ...[
        e.category,
        for (final (name, _) in e.parts) name,
      ],
    };
    return Import(
      chosen,
      skipped,
      accounts: [
        for (final a in accounts)
          if (accountsUsed.contains(a.id)) a,
      ],
      categories: [
        for (final c in categories)
          if (categoriesUsed.contains(c.name)) c,
      ],
      problems: problems,
    );
  }
}

/// How an import tells a line already in the book, as the import form
/// explains it.
const duplicateRules =
    'CSV：編號已在帳本裡；或同一天、同類型、同金額、同帳戶、同備註（轉帳再看轉入帳戶，'
    '股票再看代號與股數）都相同，就當作已經記過。'
    '電子發票：備註裡已有同一個發票號碼；或同一天、同商家、同金額、'
    '標了「發票」標籤的紀錄。檔案裡重複的發票也只算一次。';

/// Adds what [found] holds with [commands], its new accounts and categories
/// with its entries, as one change; the [Undo] takes it back (D82).
Undo addImport(EntryCommands commands, Import found) => commands.addAll(
  found.entries,
  accounts: found.accounts,
  categories: found.categories,
);

/// The kind of line [e] is written as.
LineKind _kindOf(Entry e) => switch (e) {
  Entry(isRefund: true) => LineKind.refund,
  Entry(type: EntryType.expense) => LineKind.expense,
  Entry(type: EntryType.income) => LineKind.income,
  Entry(type: EntryType.transfer) => LineKind.transfer,
  Entry(type: EntryType.buy) => LineKind.buy,
  Entry(type: EntryType.sell) => LineKind.sell,
  Entry(type: EntryType.dividend, split: true) => LineKind.split,
  Entry(type: EntryType.dividend, shares: < 0) => LineKind.cut,
  Entry(type: EntryType.dividend, shares: > 0) => LineKind.stock,
  Entry(type: EntryType.dividend) => LineKind.cash,
};

/// How the file writes an entry's [mark] (D52).
LineMark? _lineMark(EntryMark? mark) => switch (mark) {
  null => null,
  EntryMark.reward => LineMark.reward,
  EntryMark.annualFee => LineMark.annualFee,
  EntryMark.invoice => LineMark.invoice,
};

/// The entry's mark a file's [mark] names.
EntryMark? _entryMark(LineMark? mark) => switch (mark) {
  null => null,
  LineMark.reward => EntryMark.reward,
  LineMark.annualFee => EntryMark.annualFee,
  LineMark.invoice => EntryMark.invoice,
};

/// [entries] in the order a file holds them: by day, a refund after the
/// spending of its day, and otherwise in the order given, so the same
/// book writes the same file and a file read back writes itself again.
List<Entry> exportOrder(Iterable<Entry> entries) {
  final placed = [...entries.indexed]
    ..sort((a, b) {
      final byDay = a.$2.date.compareTo(b.$2.date);
      if (byDay != 0) return byDay;
      final refunds = (a.$2.isRefund ? 1 : 0) - (b.$2.isRefund ? 1 : 0);
      return refunds != 0 ? refunds : a.$1.compareTo(b.$1);
    });
  return [for (final (_, e) in placed) e];
}

/// [entries] ([exportOrder]) as CSV with the header line of
/// [ExchangeColumn], which Excel opens as UTF-8. Every kind of entry is
/// written with what it takes to read it back as it was: amounts in their
/// account's currency, a split as 分類=金額;分類=金額, fees and taxes in
/// NT$, its id, and the ids of what it refunds, is written with and books.
String toCsv(AccountReader accounts, List<Entry> entries) => writeCsv([
  exchangeHeader,
  for (final e in exportOrder(entries)) _row(accounts, e),
]);

List<String> _row(AccountReader accounts, Entry e) {
  final account = accounts.resolve(e.account);
  final to = e.to == null ? null : accounts.resolve(e.to!);
  final currency = account.currency;
  final received = e.received;
  String cell(ExchangeColumn column) => switch (column) {
    ExchangeColumn.date => ExchangeColumn.date.cell.write(
      BusinessDate.of(e.date),
    ),
    ExchangeColumn.kind => ExchangeColumn.kind.cell.write(_kindOf(e)),
    ExchangeColumn.amount => ExchangeColumn.amount.cell.write(
      e.amount,
      currency,
    ),
    ExchangeColumn.account => ExchangeColumn.account.cell.write(account.name),
    ExchangeColumn.into => ExchangeColumn.into.cell.write(to?.name),
    ExchangeColumn.category => ExchangeColumn.category.cell.write(
      e.category,
      e.parts,
      currency,
    ),
    ExchangeColumn.merchant => ExchangeColumn.merchant.cell.write(e.merchant),
    ExchangeColumn.tags => ExchangeColumn.tags.cell.write(e.tags),
    ExchangeColumn.note => ExchangeColumn.note.cell.write(e.note),
    ExchangeColumn.code => ExchangeColumn.code.cell.write(e.holding),
    ExchangeColumn.shares => ExchangeColumn.shares.cell.write(e.shares.abs()),
    // A trade's fee and tax are in NT$.
    ExchangeColumn.fee => ExchangeColumn.fee.cell.write(
      e.fee == 0 ? null : e.fee,
      homeCode,
    ),
    ExchangeColumn.tax => ExchangeColumn.tax.cell.write(
      e.tax == 0 ? null : e.tax,
      homeCode,
    ),
    ExchangeColumn.installments => ExchangeColumn.installments.cell.write(
      e.installments,
    ),
    ExchangeColumn.received => ExchangeColumn.received.cell.write(
      to == null ? null : received,
      to?.currency ?? homeCode,
    ),
    ExchangeColumn.home => ExchangeColumn.home.cell.write(e.home, homeCode),
    ExchangeColumn.costing => ExchangeColumn.costing.cell.write(
      average: e.type == EntryType.sell && e.average,
    ),
    ExchangeColumn.dayTrade => ExchangeColumn.dayTrade.cell.write(e.dayTrade),
    ExchangeColumn.mark => ExchangeColumn.mark.cell.write(_lineMark(e.mark)),
    ExchangeColumn.id => ExchangeColumn.id.cell.write(e.id),
    ExchangeColumn.refundOf => ExchangeColumn.refundOf.cell.write(e.refundOf),
    ExchangeColumn.group => ExchangeColumn.group.cell.write(e.group),
    ExchangeColumn.recurring => ExchangeColumn.recurring.cell.write(
      e.recurring,
    ),
  };
  return [for (final column in ExchangeColumn.values) cell(column)];
}

/// The day [read], as a UTC midnight; null when it was refused.
DateTime? _utcDay(ImportDay read) => switch (read) {
  DayRead(date: BusinessDate(:final year, :final month, :final day)) =>
    DateTime.utc(year, month, day),
  DayRefused() => null,
};

/// The amount in [column] of a line, read by [cell], in [currency]: its
/// minor units (null when left empty), or why it is not an amount.
(int?, String?) _cellAmount(
  String Function(ExchangeColumn) cell,
  ExchangeColumn<AmountCell> column, [
  String currency = homeCode,
]) => switch (column.cell.read(cell(column), currency)) {
  AmountOk(:final minor) => (minor, null),
  AmountRefused(problem: AmountProblem.empty) => (null, null),
  AmountRefused(:final problem) => (
    null,
    unreadableColumn(column.name, problem),
  ),
};

/// Every kind of entry in [text], CSV with a header naming at least the
/// required columns ([ExchangeColumn.required]: 日期 and 金額); the other
/// columns of [toCsv] are read when there. Without a type a negative
/// amount is spending. An account or category the book does not have is
/// added, its kind told by its name (信用卡, 現金, 錢包…); a line without
/// an account goes to [fallback]. A line whose 編號 the book has, or that
/// matches an entry already in the book, is left out, and so is one the
/// book would refuse, such as a sale of more shares than are held then.
///
/// A quote left open, or words after a closing one, leave the whole file
/// out, naming the line: the rest of it is never run into one cell. Each
/// line left out is named by the line of the file it is on, blank lines
/// and line breaks inside quoted words counted.
///
/// The same pipeline as [importCsvApart], all at once: for the tests
/// (the baseline among them); the app imports with [importCsvApart].
@visibleForTesting
Import importCsv(ImportBook book, String text, {required String fallback}) =>
    switch (_readCsv(text)) {
      (rows: final rows?, unreadable: _) => _importing(
        book,
        rows,
        fallback,
      ).last!,
      (rows: _, :final unreadable) => _unreadableFile(unreadable!),
    };

/// [importCsv] without holding the screen still: a long [text] is read
/// as CSV on a worker isolate, and its lines are read a slice of time at
/// a time ([importSlice]), the screen drawn between slices.
Future<Import> importCsvApart(
  ImportBook book,
  String text, {
  required String fallback,
}) async {
  final read = text.length < readApartFrom
      ? _readCsv(text)
      : await compute(_readCsv, text);
  final rows = read.rows;
  if (rows == null) return _unreadableFile(read.unreadable!);
  final slice = Stopwatch()..start();
  Import? found;
  for (final step in _importing(book, rows, fallback)) {
    found = step;
    if (slice.elapsed > importSlice) {
      await Future<void>.delayed(Duration.zero);
      slice.reset();
    }
  }
  return found!;
}

/// From how many characters [importCsvApart] reads a file as CSV on a
/// worker isolate: a shorter one is read in a few milliseconds.
const readApartFrom = 100000;

// Exception to the motion scale: a share of a frame's time, not a
// movement.
/// How long [importCsvApart] reads lines before the screen is drawn:
/// half a frame at 60 Hz.
const importSlice = Duration(milliseconds: 8);

/// [text] read as CSV: its records, or the line of a quote that cannot be
/// read.
({List<CsvRecord>? rows, int? unreadable}) _readCsv(String text) {
  try {
    return (rows: readCsvRecords(text), unreadable: null);
  } on CsvFormatException catch (error) {
    // Said to the person: the file is left as it is rather than guessed at.
    return (rows: null, unreadable: error.line);
  }
}

/// The whole file left out for a quote that cannot be read on [line].
Import _unreadableFile(int line) =>
    Import(const [], 1, problems: ['第 $line 行的引號看不懂，整個檔案沒有匯入']);

/// The steps of importing [rows]: null after each line read, then what
/// was found, last.
Iterable<Import?> _importing(
  ImportBook book,
  List<CsvRecord> rows,
  String fallback,
) sync* {
  if (rows.isEmpty) {
    yield const Import([], 0);
    return;
  }
  final head = ExchangeHeader(rows.first.cells);
  if (head.missing.isNotEmpty) {
    yield Import(const [], rows.length, problems: [importHeaderWords]);
    return;
  }
  final reader = _Reader(book, fallback);
  for (final (:line, cells: row) in rows.skip(1)) {
    final problem = reader.read((column) => head.cell(row, column), line: line);
    if (problem != null) reader.skip(line, problem);
    yield null;
  }
  yield* reader.result();
}
