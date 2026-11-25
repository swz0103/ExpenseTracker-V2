// Exception to shared words: a CSV's column names are a file format; they
// keep their spelling whatever the screens come to say, so files written
// before read back.
import 'package:core/money/typed_text.dart' show plainText;

import 'cells.dart';

/// The columns of the app's CSV, in the order it writes them: the
/// columns of files written before first, as they were, then those added
/// since. Each has its [name] in the header, what its cells hold and how
/// they are read and written ([cell]), and whether a file without it is
/// refused ([required]): the one definition the header, the writer and
/// the reader all come from.
enum ExchangeColumn<C extends CellCodec> {
  date<DayCell>('日期', DayCell(), required: true),
  kind<KindCell>('類型', KindCell()),

  /// In the account's currency.
  amount<AmountCell>('金額', AmountCell(), required: true),
  account<TextCell>('帳戶', TextCell()),

  /// The receiving account of a transfer.
  into<TextCell>('轉入帳戶', TextCell()),
  category<CategoryCell>('分類', CategoryCell()),
  merchant<TextCell>('商家', TextCell()),
  tags<TagsCell>('標籤', TagsCell()),
  note<TextCell>('備註', TextCell()),

  /// A stock's code.
  code<TextCell>('代號', TextCell()),
  shares<CountCell>('股數', CountCell()),

  /// In NT$.
  fee<AmountCell>('手續費', AmountCell()),

  /// In NT$.
  tax<AmountCell>('稅', AmountCell()),
  installments<CountCell>('分期', CountCell()),

  /// What reached the receiving account, in its currency.
  received<AmountCell>('轉入金額', AmountCell()),

  /// In NT$.
  home<AmountCell>(homeAmountColumn, AmountCell()),
  costing<CostCell>('成本算法', CostCell()),

  /// A sale closing a position opened the same day (D6).
  dayTrade<FlagCell>('當沖', FlagCell()),

  /// What the entry is besides its kind (D52).
  mark<MarkCell>('標記', MarkCell()),

  /// The entry's own id, which the next three name.
  id<TextCell>('編號', TextCell()),

  /// The id of the spending a refund gives back.
  refundOf<TextCell>('退款對象', TextCell()),

  /// What ties entries written as one together (一起記).
  group<TextCell>('群組', TextCell()),

  /// The id of the recurring item the entry books.
  recurring<TextCell>('定期', TextCell());

  const ExchangeColumn(this.name, this.cell, {this.required = false});

  final String name;
  final C cell;
  final bool required;
}

/// The column of the app's CSV that holds an entry's worth in NT$ where
/// its account's currency is another (a foreign spending, or a refund of
/// one): the one name the file's header, its reader and what is said of
/// a row all use (review 18). A file format's word, kept as it was
/// written so files written before read back, whatever the screens say.
const homeAmountColumn = '台幣金額';

/// The header line the app writes: each column's name, in order.
List<String> get exchangeHeader => [
  for (final c in ExchangeColumn.values) c.name,
];

/// Where each column is in a file's header line: found by name, not
/// place, so a file of another app, or one with columns left out or moved,
/// reads. The first of two of one name is read.
final class ExchangeHeader {
  ExchangeHeader(List<String> names) {
    for (final (i, name) in names.indexed) {
      _at.putIfAbsent(plainText(name).trim(), () => i);
    }
  }

  final _at = <String, int>{};

  /// The columns a file must have that this header lacks, in order.
  List<ExchangeColumn> get missing => [
    for (final c in ExchangeColumn.values)
      if (c.required && !has(c)) c,
  ];

  bool has(ExchangeColumn column) => _at.containsKey(column.name);

  /// The words of [column] in [row], trimmed; empty when the file has no
  /// such column or the row stops before it.
  String cell(List<String> row, ExchangeColumn column) {
    final at = _at[column.name];
    return at == null || at >= row.length ? '' : plainText(row[at]).trim();
  }
}
