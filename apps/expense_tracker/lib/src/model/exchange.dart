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

/// A field as CSV writes it: quoted when it holds a comma, a quote or a
/// line break, with its quotes doubled.
String csvField(String value) {
  if (!value.contains(RegExp('[",\n\r]'))) return value;
  return '"${value.replaceAll('"', '""')}"';
}

/// [entries], oldest first, as CSV with a header line.
String toCsv(Ledger ledger, List<Entry> entries) {
  final sorted = [...entries]..sort((a, b) => a.date.compareTo(b.date));
  return [
    _header.join(','),
    for (final e in sorted)
      [
        _day(e.date),
        _typeNames[e.type]!,
        '${e.amount}',
        ledger.account(e.account).name,
        e.category,
        e.merchant,
        e.tags.join(' '),
        e.note,
      ].map(csvField).join(','),
  ].join('\n');
}

String _day(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

String _two(int n) => n.toString().padLeft(2, '0');

/// The rows of [text] read as CSV: quoted fields may hold commas, quotes
/// written twice and line breaks.
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var i = 0;
  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    if (row.length > 1 || row.first.trim().isNotEmpty) rows.add(row);
    row = <String>[];
  }

  while (i < text.length) {
    final c = text[i];
    if (quoted) {
      if (c == '"' && i + 1 < text.length && text[i + 1] == '"') {
        field.write('"');
        i++;
      } else if (c == '"') {
        quoted = false;
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      endField();
    } else if (c == '\n') {
      endRow();
    } else if (c != '\r') {
      field.write(c);
    }
    i++;
  }
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
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

int? _amount(String text) {
  final value = double.tryParse(text.replaceAll(RegExp(r'[,\s$]'), ''));
  return value?.round();
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
    final value = _amount(cell(row, amount));
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
      account: names[cell(row, account)] ?? fallback,
      category: known.contains(named)
          ? named
          : income
          ? '其他收入'
          : Ledger.feeCategory,
      note: cell(row, note),
      merchant: income ? '' : cell(row, merchant),
      tags: [
        for (final t in cell(row, tags).split(RegExp(r'[\s;、]+')))
          if (t.isNotEmpty) t,
      ],
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
  return Ledger.feeCategory;
}

/// Spending from the Ministry of Finance e-invoice export: an M line per
/// invoice (載具名稱|載具號碼|日期|統編|店名|發票號碼|總金額|狀態) and D
/// lines with its items. Each invoice becomes spending on [account] at
/// the shop, noted with its invoice number; void ones and invoices
/// already in the book are left out.
Import importInvoices(Ledger ledger, String text, {required String account}) {
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
    final what = bought.isEmpty ? '' : bought.first;
    final more = bought.length > 1 ? ' 等 ${bought.length} 項' : '';
    entries.add(
      Entry(
        id: ledger.newId(),
        date: day,
        type: EntryType.expense,
        amount: value,
        account: account,
        category: guessCategory(ledger, shop, bought.join(' ')),
        note: '$what$more 發票 $number'.trim(),
        merchant: shop,
        tags: const ['發票'],
      ),
    );
  }
  return Import(entries, skipped);
}

bool _hasInvoice(Ledger ledger, DateTime? day, String number) {
  if (day == null) return false;
  return ledger
      .entriesIn(day.year, day.month)
      .any((e) => e.note.contains(number));
}
