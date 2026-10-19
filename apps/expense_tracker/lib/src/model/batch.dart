import 'checks.dart';
import 'ledger.dart';

/// Changes made to many entries at once, from the record list. Each
/// changes only the entries it fits and says how many that was.
extension BatchEdits on Ledger {
  /// Puts the spending or income among [entries] under [name]. Splits,
  /// refunds and entries of the other kind keep their own.
  int recategorize(Iterable<Entry> entries, String name) {
    final income = category(name).income;
    var changed = 0;
    for (final e in [...entries]) {
      if (!_plain(e) || e.parts.isNotEmpty || e.category == name) continue;
      if ((e.type == EntryType.income) != income) continue;
      replace(e.withCategory(name));
      changed++;
    }
    return changed;
  }

  /// Moves the spending and income among [entries] to [id], an account in
  /// the same currency. Refunded spending, instalment purchases off a card
  /// and entries the ledger would refuse stay where they are.
  int moveToAccount(Iterable<Entry> entries, String id) {
    final into = account(id);
    var changed = 0;
    for (final e in [...entries]) {
      if (!_plain(e) || e.account == id) continue;
      if (account(e.account).currency != into.currency) continue;
      if (e.installments > 0 && into.kind != AccountKind.card) continue;
      if (e.type == EntryType.expense && refundable(e) != e.amount) continue;
      final moved = e.withAccount(id);
      if (problemWith(moved, replacing: e) != null) continue;
      replace(moved);
      changed++;
    }
    return changed;
  }

  /// Spending or income that is not a refund: what a batch may change.
  static bool _plain(Entry e) =>
      (e.type == EntryType.expense || e.type == EntryType.income) &&
      !e.isRefund;
}
