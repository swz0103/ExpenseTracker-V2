import 'package:domain/data_exchange.dart';
import 'package:core/foundation_values.dart' show BusinessDate, Currency;

import 'amounts.dart';
import 'ledger.dart';

/// What an import found: the entries to add and how many lines were left
/// out, as already in the book or unreadable.
final class Import {
  const Import(this.entries, this.skipped);

  final List<Entry> entries;
  final int skipped;
}

const _typeNames = {
  EntryType.expense: '支出',
  EntryType.income: '收入',
  EntryType.transfer: '轉帳',
  EntryType.buy: '買進',
  EntryType.sell: '賣出',
  EntryType.dividend: '股息',
};

const _header = ['日期', '類型', '金額', '帳戶', '分類', '商家', '標籤', '備註'];

/// [entries], oldest first, as CSV with a header line that Excel opens
/// as UTF-8. Amounts are in their account's currency, with its decimals.
String toCsv(Ledger ledger, List<Entry> entries) {
  final sorted = [...entries]..sort((a, b) => a.date.compareTo(b.date));
  return writeCsv([
    _header,
    for (final e in sorted)
      [
        _day(e.date),
        _typeNames[e.type]!,
        plainIn(e.amount, ledger.account(e.account).currency),
        ledger.account(e.account).name,
        e.category,
        e.merchant,
        e.tags.join(' '),
        e.note,
      ],
  ]);
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
int? _amount(String text, [String currency = 'TWD']) {
  final value = text.replaceAll(RegExp(r'[,\s$]|NT'), '');
  final exact = minorOf(value, currency);
  if (exact != null) return exact;
  final rounded = double.tryParse(value);
  if (rounded == null) return null;
  return (rounded * (Currency.scaleOf(currency) == 0 ? 1 : 100)).round();
}

/// Income and spending in [text], CSV with a header naming at least
/// 日期 and 金額; 類型, 帳戶, 分類, 商家, 標籤 and 備註 are read when there.
/// Without a type a negative amount is spending. Unknown accounts go to
/// [fallback], unknown categories to the 其他 ones; a line matching an
/// entry already in the book is left out.
Import importCsv(Ledger ledger, String text, {required String fallback}) {
  final rows = parseCsv(text);
  if (rows.isEmpty) return const Import([], 0);
  final head = [for (final h in rows.first) h.trim()];
  int at(String name) => head.indexOf(name);
  final date = at('日期');
  final amount = at('金額');
  if (date < 0 || amount < 0) return Import(const [], rows.length);
  final type = at('類型');
  final account = at('帳戶');
  final category = at('分類');
  final merchant = at('商家');
  final tags = at('標籤');
  final note = at('備註');
  String cell(List<String> row, int i) =>
      i < 0 || i >= row.length ? '' : row[i].trim();
  final names = {for (final a in ledger.accounts) a.name: a.id};
  final entries = <Entry>[];
  var skipped = 0;
  for (final row in rows.skip(1)) {
    final day = readDay(cell(row, date));
    final into = names[cell(row, account)] ?? fallback;
    final currency = ledger.account(into).currency;
    final value = _amount(cell(row, amount), currency);
    final kind = cell(row, type);
    final income =
        kind == '收入' ||
        kind == 'income' ||
        (kind.isEmpty && value != null && value > 0);
    final spending =
        kind == '支出' ||
        kind == 'expense' ||
        (kind.isEmpty && value != null && value < 0);
    if (day == null || value == null || value == 0 || !(income || spending)) {
      skipped++;
      continue;
    }
    final named = cell(row, category);
    final known = ledger.categoriesFor(income: income).map((c) => c.name);
    final entry = Entry(
      id: ledger.newId(),
      date: day,
      type: income ? EntryType.income : EntryType.expense,
      amount: value.abs(),
      account: into,
      category: known.contains(named)
          ? named
          : income
          ? '其他收入'
          : feeCategory,
      note: cell(row, note),
      merchant: income ? '' : cell(row, merchant),
      tags: [
        for (final t in cell(row, tags).split(RegExp(r'[\s;、]+')))
          if (t.isNotEmpty) t,
      ],
      home: currency == 'TWD' ? null : ledger.toHome(value.abs(), currency),
    );
    if (_already(ledger, entry)) {
      skipped++;
    } else {
      entries.add(entry);
    }
  }
  return Import(entries, skipped);
}

bool _already(Ledger ledger, Entry entry) => ledger
    .entriesIn(entry.date.year, entry.date.month)
    .any(
      (e) =>
          e.date == entry.date &&
          e.type == entry.type &&
          e.amount == entry.amount &&
          e.account == entry.account &&
          e.note == entry.note,
    );

/// Words that tell a merchant's category when the book has not seen it.
const _hints = {
  '交通通勤': ['加油', '中油', '台塑', '停車', '捷運', '高鐵', '台鐵', '客運', 'Uber'],
  '飲食日常': ['7-ELEVEN', '統一超商', '全家', '萊爾富', '咖啡', '餐', '麵', '飯', '食品'],
  '居家生活': ['全聯', '家樂福', '大潤發', '屈臣氏', '康是美', '寶雅', 'IKEA'],
  '購物休閒': ['MOMO', 'PChome', '蝦皮', '誠品', '影城', '百貨'],
};

/// The category for spending at [merchant]: the one the book used last,
/// else one its name hints at, else 其他支出.
String guessCategory(Ledger ledger, String merchant, String items) {
  final used = ledger.categoryAt(merchant);
  if (used != null) return used;
  final known = ledger.categoriesFor(income: false).map((c) => c.name);
  final text = '$merchant $items'.toUpperCase();
  for (final MapEntry(key: category, value: words) in _hints.entries) {
    if (!known.contains(category)) continue;
    if (words.any((w) => text.contains(w.toUpperCase()))) return category;
  }
  return feeCategory;
}

/// Spending from the Ministry of Finance e-invoice export: an M line per
/// invoice (載具名稱|載具號碼|日期|統編|店名|發票號碼|總金額|狀態) and D
/// lines with its items. Each invoice becomes spending on [account] at
/// the shop, noted with its invoice number; void ones and invoices
/// already in the book are left out. The ministry's 消費明細 CSV, with a
/// 發票號碼 column, is read too.
Import importInvoices(Ledger ledger, String text, {required String account}) {
  if (text.contains('發票號碼')) {
    return _invoiceCsv(ledger, text, account: account);
  }
  final items = <String, List<String>>{};
  final heads = <List<String>>[];
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    final cells = line.split('|').map((c) => c.trim()).toList();
    if (cells.first == 'M' && cells.length >= 8) heads.add(cells);
    if (cells.first == 'D' && cells.length >= 4) {
      (items[cells[1]] ??= []).add(cells[3]);
    }
  }
  final entries = <Entry>[];
  var skipped = 0;
  for (final cells in heads) {
    final day = readDay(cells[3]);
    final shop = cells[5];
    final number = cells[6];
    final value = _amount(cells[7]);
    final voided = cells.length > 8 && cells[8].contains('作廢');
    final seen =
        number.isNotEmpty &&
        (entries.any((e) => e.note.contains(number)) ||
            _hasInvoice(ledger, day, number));
    if (day == null || value == null || value <= 0 || voided || seen) {
      skipped++;
      continue;
    }
    final bought = items[number] ?? const [];
    entries.add(_invoice(ledger, account, day, shop, number, bought, value));
  }
  return Import(entries, skipped);
}

/// The ministry's 消費明細 CSV, one row per item, added up per invoice by
/// `data_exchange`. A row it cannot read leaves the whole file out.
Import _invoiceCsv(Ledger ledger, String text, {required String account}) {
  final List<EInvoice> invoices;
  try {
    invoices = parseEInvoices(text);
  } on FormatException {
    return const Import([], 1);
  }
  final entries = <Entry>[];
  var skipped = 0;
  for (final invoice in invoices) {
    final BusinessDate(:year, :month, :day) = invoice.date;
    final date = DateTime.utc(year, month, day);
    final number = invoice.number;
    final value = invoice.amount.minorUnits.toInt();
    if (value <= 0 ||
        entries.any((e) => e.note.contains(number)) ||
        _hasInvoice(ledger, date, number)) {
      skipped++;
      continue;
    }
    entries.add(
      _invoice(
        ledger,
        account,
        date,
        invoice.seller,
        number,
        invoice.items,
        value,
      ),
    );
  }
  return Import(entries, skipped);
}

/// Spending at [shop] on [day] for the invoice [number], noted with its
/// first item and how many there were.
Entry _invoice(
  Ledger ledger,
  String account,
  DateTime day,
  String shop,
  String number,
  List<String> bought,
  int value,
) {
  final what = bought.isEmpty ? '' : bought.first;
  final more = bought.length > 1 ? ' 等 ${bought.length} 項' : '';
  return Entry(
    id: ledger.newId(),
    date: day,
    type: EntryType.expense,
    amount: value,
    account: account,
    category: guessCategory(ledger, shop, bought.join(' ')),
    note: '$what$more 發票 $number'.trim(),
    merchant: shop,
    tags: const ['發票'],
  );
}

bool _hasInvoice(Ledger ledger, DateTime? day, String number) {
  if (day == null) return false;
  return ledger
      .entriesIn(day.year, day.month)
      .any((e) => e.note.contains(number));
}
