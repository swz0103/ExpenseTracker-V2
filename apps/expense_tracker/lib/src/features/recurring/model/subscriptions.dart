import '../../../core/ledger/ledger.dart';

import 'package:core/time/utc_days.dart';

/// 訂閱總覽: each active spending item with what it costs over the next
/// twelve months (this month on), the dearest first.
List<(Recurring, int)> yearlyCosts(
  RecurringReader recurring,
  RecurringService service, {
  required DateTime today,
}) {
  final rows = <(Recurring, int)>[];
  for (final r in recurring.all) {
    if (!r.active || r.income) continue;
    var times = 0;
    for (var k = 0; k < 12; k++) {
      final month = monthStart(today, k);
      times += r.datesIn(month.year, month.month).length;
    }
    if (times == 0) continue;
    rows.add((r, service.worth(r) * times));
  }
  return rows..sort((a, b) => b.$2.compareTo(a.$2));
}
