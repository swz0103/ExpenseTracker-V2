import '../../../core/ledger/ledger.dart';
import 'compose_form.dart';

// 拆分: an entry's parts by category, and the ends of a transfer or trade.

extension Splitting on ComposeForm {
  /// Splits the amount into parts, or puts it back into one; not while
  /// paying for others.
  void toggleSplit() {
    if (lending) return;
    parts = parts == null ? [(category, amount)] : null;
  }

  /// Shares the amount evenly over the parts; the last takes what is
  /// left over.
  void evenly() {
    final now = parts;
    if (now == null || now.isEmpty) return;
    final each = amount ~/ now.length;
    parts = [
      for (final (i, (name, _)) in now.indexed)
        (name, i == now.length - 1 ? amount - each * (now.length - 1) : each),
    ];
  }

  /// Adds a part for [name] with what is not yet shared out.
  void addPart(String name) {
    final now = parts ?? [];
    final used = now.fold(0, (sum, p) => sum + p.$2);
    parts = [...now, (name, amount - used)];
  }

  /// Adds a part for [name], or takes away the one it has: a tap on a
  /// category while splitting.
  void togglePart(String name) {
    final now = parts ?? [];
    final at = now.indexWhere((p) => p.$1 == name);
    if (at < 0) {
      addPart(name);
    } else {
      parts = [
        for (final (i, p) in now.indexed)
          if (i != at) p,
      ];
    }
  }

  /// The two accounts of a transfer the other way round.
  void swapEnds() {
    final from = account;
    account = to;
    to = from;
    received = null;
  }

  /// Starts a new transfer from [entry], one of `EntryQueryService.usualTransfers`:
  /// its two accounts and amount, on today.
  void startTransferFrom(Entry entry) {
    final open = {for (final a in ledger.accounts.open) a.id};
    final other = entry.to;
    if (!open.contains(entry.account) ||
        other == null ||
        !open.contains(other)) {
      return;
    }
    account = entry.account;
    to = other;
    setAmount(entry.amount);
  }

  /// Changes the part at [index] to [value]; zero takes it away.
  void setPart(int index, int value) {
    final now = parts;
    if (now == null) return;
    parts = [
      for (final (i, p) in now.indexed)
        if (i != index) p else if (value > 0) (p.$1, value),
    ];
  }

  /// Moving between a trade and a dividend starts the shares afresh: a
  /// dividend's are the ones it adds.
  void changeTrade(EntryType next) {
    if ((next == EntryType.dividend) != (trade == EntryType.dividend)) {
      shares = 0;
      amount = 0;
      splitShares = false;
      shareChange = false;
      reduce = false;
    }
    tradeFee = null;
    tradeTax = null;
    trade = next;
  }

  /// The parts of a split being written; none for a foreign amount.
  List<(String, int)>? get splitParts =>
      type == EntryType.expense && !foreign ? parts : null;

  /// A dividend that changes the shares held: a stock dividend, a split
  /// or, with [reduce], a capital reduction.
  bool get stock => type == EntryType.dividend && shares > 0;
  bool get reducing => stock && reduce;

  /// What of the amount the parts have not taken yet: none when they add
  /// up to it, below none when they take more.
  int get splitLeft =>
      amount - (parts ?? const <(String, int)>[]).fold(0, (s, p) => s + p.$2);

  /// The categories in the row under the amount: four of the most used,
  /// as many as it shows without sliding; the one chosen in place of the
  /// last when it is not among them, and while splitting each part's.
  /// [more] is whether 全部 follows, for those not shown or parts to add.
  ({List<String> shown, bool more}) categoryRow() {
    final choices = categoryChoices();
    final shown = choices.take(4).toList();
    final splitting = parts != null;
    if (!splitting &&
        category.isNotEmpty &&
        !shown.contains(category) &&
        shown.isNotEmpty) {
      shown[shown.length - 1] = category;
    }
    for (final (name, _) in parts ?? const <(String, int)>[]) {
      if (!shown.contains(name)) shown.add(name);
    }
    return (shown: shown, more: choices.length > shown.length || splitting);
  }
}
