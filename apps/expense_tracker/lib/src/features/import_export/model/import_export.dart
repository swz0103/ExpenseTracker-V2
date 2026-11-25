// Exception to shared words: a CSV's columns and kinds are a file
// format; they keep their spelling whatever the screens come to say.
import 'package:core/constants/category_colors.dart';
import 'package:core/foundation_values.dart' show BusinessDate, Currency;
import 'package:core/money/amount_parser.dart';
import 'package:core/money/typed_text.dart' show plainText;
import 'package:domain/data_exchange.dart';
import 'package:flutter/foundation.dart' show compute, visibleForTesting;

import '../../../../design_system/display/amount.dart';
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
    'CSV：同一天、同類型、同金額、同帳戶、同備註（轉帳再看轉入帳戶，'
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

const _header = [
  '日期',
  '類型',
  '金額',
  '帳戶',
  '轉入帳戶',
  '分類',
  '商家',
  '標籤',
  '備註',
  '代號',
  '股數',
  '手續費',
  '稅',
  '分期',
  '轉入金額',
  homeAmountColumn,
  '成本算法',
];

/// The name an entry's kind has in a CSV.
String _typeOf(Entry e) => switch (e) {
  Entry(isRefund: true) => '退款',
  Entry(type: EntryType.expense) => '支出',
  Entry(type: EntryType.income) => '收入',
  Entry(type: EntryType.transfer) => '轉帳',
  Entry(type: EntryType.buy) => '買進',
  Entry(type: EntryType.sell) => '賣出',
  Entry(type: EntryType.dividend, split: true) => '分割',
  Entry(type: EntryType.dividend, shares: < 0) => '減資',
  Entry(type: EntryType.dividend, shares: > 0) => '配股',
  Entry(type: EntryType.dividend) => '股息',
};

/// [entries], oldest first, as CSV with a header line that Excel opens
/// as UTF-8. Every kind of entry is written with what it takes to read
/// it back: amounts in their account's currency, a split as
/// 分類=金額;分類=金額, fees and taxes in NT$.
String toCsv(AccountReader accounts, List<Entry> entries) {
  final sorted = [...entries]..sort((a, b) => a.date.compareTo(b.date));
  return writeCsv([_header, for (final e in sorted) _row(accounts, e)]);
}

List<String> _row(AccountReader accounts, Entry e) {
  String count(int n) => n == 0 ? '' : '$n';
  final account = accounts.resolve(e.account);
  final to = e.to == null ? null : accounts.resolve(e.to!);
  final received = e.received;
  return [
    _day(e.date),
    _typeOf(e),
    plainIn(e.amount, account.currency),
    account.name,
    to?.name ?? '',
    if (e.parts.isEmpty)
      e.category
    else
      [
        for (final (name, part) in e.parts)
          '$name=${plainIn(part, account.currency)}',
      ].join(';'),
    e.merchant,
    e.tags.join('、'),
    e.note,
    e.holding ?? '',
    count(e.shares.abs()),
    count(e.fee),
    count(e.tax),
    count(e.installments),
    if (received == null || to == null) '' else plainIn(received, to.currency),
    e.home == null ? '' : '${e.home}',
    e.type == EntryType.sell && e.average ? '平均成本' : '',
  ];
}

/// The tags of a CSV cell: split at 、 or ; when it has them, so a tag
/// may hold a space, else at spaces, as one typed by hand.
List<String> _tagsIn(String cell) => [
  for (final t in cell.split(
    RegExp(cell.contains(RegExp('[;；、]')) ? r'[;；、]+' : r'\s+'),
  ))
    t.trim(),
];

/// Whether a category cell is a split, every part 「名稱=金額」, rather
/// than a name that holds an =.
bool _isSplit(String cell) {
  final pieces = cell.split(RegExp('[;；]'));
  return pieces.every((p) => RegExp(r'=\s*[\d,.]+\s*$').hasMatch(p));
}

String _day(DateTime d) => BusinessDate.of(d).toString();

/// The rows of [text] read as CSV, a leading byte order mark and blank
/// lines left out, a quote left open read to the end, as a spreadsheet
/// reads it; words after a closing quote throw [CsvFormatException]. Not
/// what an import reads: [importCsv] refuses a quote left open, the whole
/// file, rather than run the rest of it into one cell.
///
/// Read by the tests that pin how a spreadsheet's CSV is read (the
/// baseline among them); the app imports with [importCsvApart].
@visibleForTesting
List<List<String>> parseCsv(String text) {
  try {
    return readCsv(text);
  } on CsvFormatException catch (error) {
    if (!error.unclosed) rethrow;
    // An unclosed quote is closed at the end of the text and read again.
    return readCsv('$text"');
  }
}

/// The day [text] writes ([readImportDay], decision D93), as a UTC
/// midnight; null when it is not taken, [readImportDay] saying why.
/// For the tests (the baseline among them): an import reads its days
/// with [readImportDay].
@visibleForTesting
DateTime? readDay(String text) => _utcDay(readImportDay(text));

/// The day [read], as a UTC midnight; null when it was refused.
DateTime? _utcDay(ImportDay read) => switch (read) {
  DayRead(date: BusinessDate(:final year, :final month, :final day)) =>
    DateTime.utc(year, month, day),
  DayRefused() => null,
};

/// [text] in the smallest unit of [currency]: `1,200` and `NT$ 120` read
/// as written, more decimals than the currency has are rounded. What
/// could be read more than one way, such as `1.234,50` or `1 200`, is
/// refused with its reason rather than guessed at.
AmountResult _amount(String text, [String currency = homeCode]) {
  final value = text.trim().replaceFirstMapped(
    RegExp(r'^([-−+]?)\s*(?:NT)?\$\s*'),
    (m) => m[1]!,
  );
  return parseAmount(
    value,
    scale: Currency.scaleOf(currency),
    decimals: Decimals.round,
  );
}

/// The amount in [column] of a line, read by [cell], in [currency]: its
/// minor units (null when left empty), or why it is not an amount.
(int?, String?) _cellAmount(
  String Function(String) cell,
  String column, [
  String currency = homeCode,
]) => switch (_amount(cell(column), currency)) {
  AmountOk(:final minor) => (minor, null),
  AmountRefused(problem: AmountProblem.empty) => (null, null),
  AmountRefused(:final problem) => (null, unreadableColumn(column, problem)),
};

/// The kinds a CSV line can be, by the names it may use.
enum _Kind {
  expense,
  income,
  transfer,
  buy,
  sell,
  cash,
  stock,
  split,
  cut,
  refund,
}

const _kinds = {
  '支出': _Kind.expense,
  'expense': _Kind.expense,
  '收入': _Kind.income,
  'income': _Kind.income,
  '轉帳': _Kind.transfer,
  'transfer': _Kind.transfer,
  '買進': _Kind.buy,
  '買入': _Kind.buy,
  'buy': _Kind.buy,
  '賣出': _Kind.sell,
  'sell': _Kind.sell,
  '股息': _Kind.cash,
  // Exception to glossary: a word brokers write, read on import.
  '現金股利': _Kind.cash,
  'dividend': _Kind.cash,
  '配股': _Kind.stock,
  // Exception to glossary: a word brokers write, read on import.
  '股票股利': _Kind.stock,
  '分割': _Kind.split,
  '減資': _Kind.cut,
  '退款': _Kind.refund,
  'refund': _Kind.refund,
};

/// Every kind of entry in [text], CSV with a header naming at least 日期
/// and 金額; the other columns of [toCsv] are read when there. Without a
/// type a negative amount is spending. An account or category the book
/// does not have is added, its kind told by its name (信用卡, 現金,
/// 錢包…); a line without an account goes to [fallback]. A line matching
/// an entry already in the book is left out, and so is one the book
/// would refuse, such as a sale of more shares than are held then.
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
  final head = [for (final h in rows.first.cells) plainText(h).trim()];
  if (!head.contains('日期') || !head.contains('金額')) {
    yield Import(const [], rows.length, problems: const ['第一行要有「日期」和「金額」欄位']);
    return;
  }
  final reader = _Reader(book, fallback);
  for (final (:line, cells: row) in rows.skip(1)) {
    String cell(String name) {
      final at = head.indexOf(name);
      return at < 0 || at >= row.length ? '' : plainText(row[at]).trim();
    }

    final problem = reader.read(cell, line: line);
    if (problem != null) reader.skip(line, problem);
    yield null;
  }
  yield* reader.result();
}
