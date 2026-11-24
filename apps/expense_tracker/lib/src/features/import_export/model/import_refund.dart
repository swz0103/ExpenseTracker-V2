// Exception to shared words: the CSV columns read, as written by
// import_export.dart and by other apps; a file format, not screen words.
part of 'import_export.dart';

/// A refund read from a file: the spending it gives back, and its share.
extension _Refunds on _Reader {
  /// A refund of the latest spending on [account] up to [day] with that
  /// much left to give back, the same shop's first. On a foreign account
  /// its worth at home is the 台幣金額 written, when it is within what of
  /// the purchase's worth is left, else its share of the purchase's
  /// worth (D62), else the amount at today's rate.
  Object _refund(
    String Function(String) cell,
    DateTime day,
    String account,
    Account from,
    int amount,
    String note,
  ) {
    final shop = cell('商家');
    final candidates = [
      // Exception to as-of-today: a duplicate check looks at every entry
      // written.
      for (final e in [...book.entries.all, for (final (_, f) in _found) f])
        if (e.type == EntryType.expense &&
            !e.isRefund &&
            e.account == account &&
            !e.date.isAfter(day) &&
            _left(e) >= amount)
          e,
    ]..sort((a, b) => b.date.compareTo(a.date));
    if (candidates.isEmpty) return '找不到可以退款的原支出';
    final original = candidates.firstWhere(
      (e) => shop.isNotEmpty && e.merchant == shop,
      orElse: () => candidates.first,
    );
    // As the composer writes it: the purchase's split and tags (D65).
    final earlier = [
      ...book.entries.refundsOf(original.id),
      for (final (_, f) in _found)
        if (f.refundOf == original.id) f,
    ];
    final share = refundShare(original, amount, earlier: earlier);
    // Exception to glossary: the file format's column, kept so files written before read back.
    final (typed, homeProblem) = _cellAmount(cell, '台幣金額');
    if (homeProblem != null) return homeProblem;
    int? home;
    if (from.foreign) {
      // What of the purchase's worth is not yet given back: a refund of
      // all that is left takes all of it.
      final left = refundShare(
        original,
        original.amount,
        earlier: earlier,
      ).home;
      if (typed != null && typed <= 0) return refundHomeWords(null);
      if (typed != null && left != null && typed > left) {
        return refundHomeWords(left);
      }
      home =
          typed ?? share.home ?? book.marketData.toHome(amount, from.currency);
    }
    return Entry(
      id: book.newId(),
      date: day,
      type: EntryType.income,
      amount: amount,
      account: account,
      category: share.category,
      note: note,
      tags: share.tags,
      parts: share.parts,
      refundOf: original.id,
      home: home,
    );
  }

  int _left(Entry e) {
    final inBook = book.entries.byId(e.id) == null
        ? e.amount
        : book.entryQueryService.refundable(e);
    return inBook - (_refunded[e.id] ?? 0);
  }
}
