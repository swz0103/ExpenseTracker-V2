// Exception to shared words: the words a cell of the app's CSV holds
// are a file format; they keep their spelling whatever the screens say.
import 'package:core/foundation_values.dart' show BusinessDate, Currency;
import 'package:core/money/amount_format.dart' show figures;
import 'package:core/money/amount_parser.dart';

import 'import_day.dart';

/// How a cell of the app's CSV is read and written: what a column holds
/// ([ExchangeColumn.cell]). Each kind reads what it writes back to the
/// same value.
sealed class CellCodec {
  const CellCodec();
}

/// A day: written as 2026-03-05, read by the import's one rule
/// ([readImportDay], decision D93).
final class DayCell extends CellCodec {
  const DayCell();

  ImportDay read(String text, {BusinessDate? latest}) =>
      readImportDay(text, latest: latest);

  String write(BusinessDate day) => day.toString();
}

/// An amount in the smallest unit of the currency it is read in: written
/// as typed into a field (`1234.50`, `300`); `1,200` and `NT$ 120` read
/// as written, more decimals than the currency has rounded. What could be
/// read more than one way, such as `1.234,50` or `1 200`, is refused with
/// its reason rather than guessed at.
final class AmountCell extends CellCodec {
  const AmountCell();

  AmountResult read(String text, String currency) => parseAmount(
    text.trim().replaceFirstMapped(_dollar, (m) => m[1]!),
    scale: Currency.scaleOf(currency),
    decimals: Decimals.round,
  );

  /// [minor] in [currency]; empty for none.
  String write(int? minor, String currency) => minor == null
      ? ''
      : figures(minor, Currency.scaleOf(currency), grouped: false);

  static final _dollar = RegExp(r'^([-−+]?)\s*(?:NT)?\$\s*');
}

/// Words as they are: a name, a note, an id.
final class TextCell extends CellCodec {
  const TextCell();

  String read(String text) => text;

  String write(String? words) => words ?? '';
}

/// A whole count, such as shares or instalments: empty for 0, thousands
/// commas read.
final class CountCell extends CellCodec {
  const CountCell();

  /// The count written; 0 for an empty cell, null for one that is not a
  /// whole number.
  int? read(String text) {
    final digits = text.replaceAll(',', '').trim();
    return digits.isEmpty ? 0 : int.tryParse(digits);
  }

  String write(int count) => count == 0 ? '' : '$count';
}

/// Yes or no: written 是 or left empty.
final class FlagCell extends CellCodec {
  const FlagCell();

  /// Whether the cell says yes; null for words that say neither.
  bool? read(String text) => switch (text.trim().toLowerCase()) {
    '' || '否' || 'false' || '0' || 'n' || 'no' => false,
    '是' || 'true' || '1' || 'y' || 'yes' => true,
    _ => null,
  };

  String write(bool yes) => yes ? _yes : '';

  static const _yes = '是';
}

/// Labels: written 家用、早餐; read split at 、 or ; when the cell has
/// them, so a tag may hold a space, else at spaces, as typed by hand.
final class TagsCell extends CellCodec {
  const TagsCell();

  List<String> read(String text) => [
    for (final t in text.split(
      RegExp(text.contains(RegExp('[;；、]')) ? r'[;；、]+' : r'\s+'),
    ))
      if (t.trim().isNotEmpty) t.trim(),
  ];

  String write(List<String> tags) => tags.join('、');
}

/// What a category cell says: one category, or a split.
sealed class CategoryRead {
  const CategoryRead();
}

/// One category by its [name] (empty when the cell is).
final class OneCategory extends CategoryRead {
  const OneCategory(this.name);

  final String name;
}

/// A split: each part's category and amount, in the order written.
final class SplitCategory extends CategoryRead {
  const SplitCategory(this.parts);

  final List<(String, int)> parts;
}

/// A split whose amounts cannot be read.
final class SplitUnreadable extends CategoryRead {
  const SplitUnreadable();
}

/// A category, or a split as 名稱=金額;名稱=金額 in the account's
/// currency. A name holding an = is a name, unless every part of the cell
/// is 名稱=金額.
final class CategoryCell extends CellCodec {
  const CategoryCell();

  /// [text] read for spending in [currency]; [split] false reads it as
  /// one name whatever it holds (income has no split). A single part is
  /// no split: the whole cell is the name, as written.
  CategoryRead read(String text, String currency, {bool split = true}) {
    final pieces = text.split(RegExp('[;；]'));
    final isSplit =
        split && pieces.every((p) => RegExp(r'=\s*[\d,.]+\s*$').hasMatch(p));
    if (!isSplit) return OneCategory(text);
    final parts = <(String, int)>[];
    for (final piece in pieces) {
      final at = piece.lastIndexOf('=');
      final part = const AmountCell()
          .read(piece.substring(at + 1), currency)
          .minorOrNull;
      if (part == null || part <= 0) return const SplitUnreadable();
      parts.add((piece.substring(0, at).trim(), part));
    }
    return parts.length == 1 ? OneCategory(text) : SplitCategory(parts);
  }

  /// [category], or [parts] in [currency] when there are any.
  String write(String category, List<(String, int)> parts, String currency) =>
      parts.isEmpty
      ? category
      : [
          for (final (name, part) in parts)
            '$name=${const AmountCell().write(part, currency)}',
        ].join(';');
}

/// The kinds a line of the app's CSV can be, each by the word written.
enum LineKind {
  expense('支出'),
  income('收入'),
  transfer('轉帳'),
  buy('買進'),
  sell('賣出'),
  // A cash dividend.
  cash('股息'),
  // A stock dividend.
  stock('配股'),
  split('分割'),
  // A capital reduction.
  cut('減資'),
  refund('退款');

  const LineKind(this.word);

  /// What the file says for it.
  final String word;
}

/// What a kind cell says.
sealed class KindRead {
  const KindRead();
}

/// A kind named, or none written ([kind] null).
final class KindNamed extends KindRead {
  const KindNamed(this.kind);

  final LineKind? kind;
}

/// Words that name no kind.
final class KindUnknown extends KindRead {
  const KindUnknown(this.words);

  final String words;
}

/// A line's kind: written by its word ([LineKind.word]); read by it or by
/// the other words people and brokers write.
final class KindCell extends CellCodec {
  const KindCell();

  KindRead read(String text) {
    if (text.isEmpty) return const KindNamed(null);
    final kind = _read[text] ?? _read[text.toLowerCase()];
    return kind == null ? KindUnknown(text) : KindNamed(kind);
  }

  String write(LineKind kind) => kind.word;

  static final _read = {
    for (final k in LineKind.values) k.word: k,
    'expense': LineKind.expense,
    'income': LineKind.income,
    'transfer': LineKind.transfer,
    '買入': LineKind.buy,
    'buy': LineKind.buy,
    'sell': LineKind.sell,
    // Exception to glossary: a word brokers write, read on import.
    '現金股利': LineKind.cash,
    'dividend': LineKind.cash,
    // Exception to glossary: a word brokers write, read on import.
    '股票股利': LineKind.stock,
    'refund': LineKind.refund,
  };
}

/// What an entry is besides its kind, for the figures that count it
/// (D52), as the file writes it.
enum LineMark {
  /// A card's cashback.
  reward('回饋'),

  /// A card's annual fee.
  annualFee('年費'),

  /// A spending read from an e-invoice.
  invoice('發票');

  const LineMark(this.word);

  final String word;
}

/// What a mark cell says.
sealed class MarkRead {
  const MarkRead();
}

/// A mark, or none ([mark] null).
final class MarkNamed extends MarkRead {
  const MarkNamed(this.mark);

  final LineMark? mark;
}

/// Words that name no mark.
final class MarkUnknown extends MarkRead {
  const MarkUnknown(this.words);

  final String words;
}

/// An entry's mark ([LineMark]), by its word; empty for none.
final class MarkCell extends CellCodec {
  const MarkCell();

  MarkRead read(String text) {
    if (text.isEmpty) return const MarkNamed(null);
    for (final mark in LineMark.values) {
      if (mark.word == text) return MarkNamed(mark);
    }
    return MarkUnknown(text);
  }

  String write(LineMark? mark) => mark?.word ?? '';
}

/// How a sale is costed: 平均成本 for the average price, empty for first
/// in, first out.
final class CostCell extends CellCodec {
  const CostCell();

  /// Whether the sale is costed at the average price.
  bool read(String text) => text.contains(_averageWord);

  String write({required bool average}) => average ? _average : '';

  static const _average = '平均成本';
  static const _averageWord = '平均';
}
