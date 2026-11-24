import '../../../core/ledger/ledger.dart';

// Exception to ledger words: the categories a merchant's name hints at,
// and the 發票 tag, are the book's own words.

/// What the book knows of e-invoices and merchants, for an entry typed,
/// scanned or imported alike: the category a merchant takes, and whether
/// an invoice is in the book already.

/// Words that tell a merchant's category when the book has not seen it.
const _hints = {
  '交通通勤': ['加油', '中油', '台塑', '停車', '捷運', '高鐵', '台鐵', '客運', 'Uber'],
  '飲食日常': ['7-ELEVEN', '統一超商', '全家', '萊爾富', '咖啡', '餐', '麵', '飯', '食品'],
  '居家生活': ['全聯', '家樂福', '大潤發', '屈臣氏', '康是美', '寶雅', 'IKEA'],
  '購物休閒': ['MOMO', 'PChome', '蝦皮', '誠品', '影城', '百貨'],
};

/// The category for spending at [merchant]: the one the book used last,
/// else one its name hints at, else 其他支出.
String guessCategory(
  EntryQueryService queries,
  CategoryReader categories,
  String merchant,
  String items,
) {
  final used = queries.categoryAt(merchant);
  if (used != null) return used;
  final known = categories.forEntries(income: false).map((c) => c.name);
  final text = '$merchant $items'.toUpperCase();
  for (final MapEntry(key: category, value: words) in _hints.entries) {
    if (!known.contains(category)) continue;
    if (words.any((w) => text.contains(w.toUpperCase()))) return category;
  }
  return feeCategory;
}

/// Whether the invoice [number] of [day] is in the book already, as an
/// import or a scan would find it.
bool invoiceRecorded(EntryReader entries, DateTime day, String number) =>
    hasInvoice(entries, day, number);

/// Whether [note] names the invoice [number] itself: as a word of its
/// own, never as the start of a longer number (AB1 is not in AB12).
bool notesInvoice(String note, String number) =>
    number.isNotEmpty &&
    RegExp('(?<![A-Za-z0-9])${RegExp.escape(number)}(?![A-Za-z0-9])')
        .hasMatch(note);

/// Whether the invoice [number] of [day] was imported before: its number
/// is in a note ([notesInvoice]), or an invoice entry of that day, shop
/// and [amount] is there, as when its note was edited since.
bool hasInvoice(
  EntryReader entries,
  DateTime? day,
  String number, {
  String shop = '',
  int? amount,
}) {
  if (day == null) return false;
  // Exception to as-of-today: a duplicate check looks at every entry written.
  return entries
      .inMonth(day.year, day.month)
      .any(
        (e) =>
            notesInvoice(e.note, number) ||
            (e.mark == EntryMark.invoice &&
                // An entry still noting its own number is another invoice.
                !e.note.contains(RegExp(r'發票 \S')) &&
                e.date == day &&
                e.merchant == shop &&
                e.amount == amount),
      );
}
