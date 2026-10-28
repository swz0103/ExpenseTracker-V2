import '../../../core/ledger/ledger.dart';

/// 訂閱總覽: each active spending item with what it costs over the next
/// twelve months (this month on), the dearest first.
List<(Recurring, int)> yearlyCosts(Ledger ledger) {
  final today = ledger.today;
  final rows = <(Recurring, int)>[];
  for (final r in ledger.recurring) {
    if (!r.active || r.income) continue;
    var times = 0;
    for (var k = 0; k < 12; k++) {
      final month = DateTime.utc(today.year, today.month + k);
      times += r.datesIn(month.year, month.month).length;
    }
    if (times == 0) continue;
    rows.add((r, ledger.recurringWorth(r) * times));
  }
  return rows..sort((a, b) => b.$2.compareTo(a.$2));
}
