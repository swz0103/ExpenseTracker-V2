import 'dart:convert';

import 'package:vault/backup_security.dart';

import '../../../../design_system/display/amount.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/formatting/dates.dart';

/// What the inbox brought when the ledger opened: how many items were
/// booked, and what could not be, for the person to look at.
typedef InboxOutcome = ({int booked, List<String> review});

/// Applies the requests written while the ledger was locked. A
/// 「確認入帳」 books its recurring item when that day is the one still
/// due, the same as confirming it on the page; one booked since (by hand
/// or by itself) is let go. Anything else is not guessed at but listed:
/// an item deleted, paused or with an earlier day still unbooked, and
/// requests that cannot be read (sealed for a ledger restored over).
InboxOutcome applyInbox(
  List<InboxItem> items, {
  required RecurringReader recurring,
  required RecurringService service,
  required RecurringCommands commands,
}) {
  var booked = 0;
  var unreadable = 0;
  final review = <String>[];
  for (final item in items) {
    final plain = item.plain;
    final request = plain == null ? null : _read(plain);
    if (request == null) {
      unreadable++;
      continue;
    }
    final (id, day) = request;
    final label = formatMd(day);
    Recurring? found;
    for (final r in recurring.all) {
      if (r.id == id) found = r;
    }
    if (found == null) {
      review.add('$label 確認的定期項目已刪除，沒有入帳');
      continue;
    }
    if (!found.active) {
      review.add('「${found.name}」已暫停，$label 的確認沒有入帳');
      continue;
    }
    final pending = service.pendingDate(found);
    if (pending == day) {
      commands.confirm(found);
      booked++;
    } else if (pending != null && pending.isBefore(day)) {
      review.add('「${found.name}」還有 ${formatMd(pending)} 那期沒入帳，請到定期交易確認');
    }
    // Otherwise that day is booked already.
  }
  if (unreadable > 0) {
    review.add(
      '有 ${countOf(unreadable, CountUnit.notes)}通知上的確認無法讀取（可能是換帳本前留下的），已略過',
    );
  }
  return (booked: booked, review: review);
}

(String, DateTime)? _read(List<int> plain) {
  try {
    final json = jsonDecode(utf8.decode(plain));
    if (json is! Map<String, Object?> || json['kind'] != 'confirm') {
      return null;
    }
    final id = json['recurring'];
    final day = json['day'];
    if (id is! String || day is! String) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(day);
    if (match == null) return null;
    return (
      id,
      DateTime.utc(
        int.parse(match[1]!),
        int.parse(match[2]!),
        int.parse(match[3]!),
      ),
    );
  } on Object {
    // A line that is not a time is left out.
    return null;
  }
}
