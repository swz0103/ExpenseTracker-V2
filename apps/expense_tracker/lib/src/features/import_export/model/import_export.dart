import 'package:core/foundation_values.dart' show BusinessDate, Currency;
import 'package:domain/data_exchange.dart';

import '../../../core/text/amounts.dart';
import '../../../core/ledger/checks.dart';
import '../../../core/ledger/ledger.dart';

part 'import_reader.dart';

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

/// Adds what [found] holds to [ledger], its new accounts and categories
/// with its entries, as one change.
void addImport(Ledger ledger, Import found) => ledger.addAll(
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
  '台幣金額',
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
String toCsv(Ledger ledger, List<Entry> entries) {
  final sorted = [...entries]..sort((a, b) => a.date.compareTo(b.date));
  return writeCsv([_header, for (final e in sorted) _row(ledger, e)]);
}

List<String> _row(Ledger ledger, Entry e) {
  String count(int n) => n == 0 ? '' : '$n';
  final account = ledger.account(e.account);
  final to = e.to == null ? null : ledger.account(e.to!);
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

String _day(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

String _two(int n) => n.toString().padLeft(2, '0');

/// The rows of [text] read as CSV, a leading byte order mark and blank
/// lines left out. A quote left open runs to the end, as a spreadsheet
/// reads it.
List<List<String>> parseCsv(String text) {
  try {
    return readCsv(text);
  } on FormatException {
    // An unclosed quote is closed at the end of the text and read again.
    return readCsv('$text"');
  }
}

/// A day written as 2026-03-05, 2026/3/5, 20260305 or, in the Republic
/// of China calendar, 1150305; null when unreadable.
DateTime? readDay(String text) {
  final value = text.trim();
  final digits = RegExp(r'^\d{7,8}$');
  if (digits.hasMatch(value)) {
    final cut = value.length - 4;
    var year = int.parse(value.substring(0, cut));
    if (value.length == 7) year += 1911;
    final month = int.parse(value.substring(cut, cut + 2));
    final day = int.parse(value.substring(cut + 2));
    return _valid(year, month, day);
  }
  final parts = value.split(RegExp(r'[-/.]'));
  if (parts.length != 3) return null;
  final numbers = parts.map(int.tryParse).toList();
  if (numbers.contains(null)) return null;
  var year = numbers[0]!;
  if (year < 1000) year += 1911;
  return _valid(year, numbers[1]!, numbers[2]!);
}

DateTime? _valid(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime.utc(year, month, day);
  return date.month == month ? date : null;
}

/// [text] in the smallest unit of [currency]: `1,200` and `NT$ 120` read
/// as written, more decimals than the currency has are rounded.
int? _amount(String text, [String currency = homeCode]) {
  final value = text.replaceAll(RegExp(r'[,\s$]|NT'), '');
  final exact = minorOf(value, currency);
  if (exact != null) return exact;
  final rounded = double.tryParse(value);
  if (rounded == null) return null;
  return (rounded * (Currency.scaleOf(currency) == 0 ? 1 : 100)).round();
}

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
  '現金股利': _Kind.cash,
  'dividend': _Kind.cash,
  '配股': _Kind.stock,
  '股票股利': _Kind.stock,
  '分割': _Kind.split,
  '減資': _Kind.cut,
  '退款': _Kind.refund,
  'refund': _Kind.refund,
};

/// Colours for categories an import adds.
const _shades = [
  0xFF5C9A83,
  0xFFD08B5B,
  0xFF5B8DB0,
  0xFF8E7CC0,
  0xFFC9A34A,
  0xFFB07A8C,
  0xFF4E8A9A,
];

/// Every kind of entry in [text], CSV with a header naming at least 日期
/// and 金額; the other columns of [toCsv] are read when there. Without a
/// type a negative amount is spending. An account or category the book
/// does not have is added, its kind told by its name (信用卡, 現金,
/// 錢包…); a line without an account goes to [fallback]. A line matching
/// an entry already in the book is left out, and so is one the book
/// would refuse, such as a sale of more shares than are held then.
Import importCsv(Ledger ledger, String text, {required String fallback}) {
  final rows = parseCsv(text);
  if (rows.isEmpty) return const Import([], 0);
  final head = [for (final h in rows.first) h.trim()];
  if (!head.contains('日期') || !head.contains('金額')) {
    return Import(const [], rows.length, problems: const ['第一行要有「日期」和「金額」欄位']);
  }
  final reader = _Reader(ledger, fallback);
  for (final (i, row) in rows.skip(1).indexed) {
    String cell(String name) {
      final at = head.indexOf(name);
      return at < 0 || at >= row.length ? '' : row[at].trim();
    }

    final problem = reader.read(cell);
    if (problem != null) reader.skip(i + 2, problem);
  }
  return reader.result();
}
