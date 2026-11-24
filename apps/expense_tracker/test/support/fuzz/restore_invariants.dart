import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a refused restore must leave exactly as it was: the entries in
/// their order, the trash (with each entry's day, place and day let go),
/// the accounts closed and each recurring item's days skipped.
String restoreState(Ledger l) => [
  'entries ${[for (final e in l.entries.all) '${e.id}@${l.entries.orderOf(e.id)}:${e.amount}']}',
  'trash ${[for (final t in l.trash.all) '${t.entry.id}/${t.on.toIso8601String()}/${t.order}/${t.letGo?.toIso8601String()}']}',
  'accounts ${[for (final a in l.accounts.all) '${a.id}:${a.archived}']}',
  'recurring ${[
    for (final r in l.recurring.all) '${r.id}:${[for (final d in r.skipped.toList()..sort()) d.toIso8601String()]}',
  ]}',
].join('\n');

/// Every id of [l], in the book or in the trash.
Set<String> idsOf(Ledger l) => {
  for (final e in l.entries.all) e.id,
  for (final t in l.trash.all) t.entry.id,
};

/// The entries and the trash part the ids: none twice in either, none in
/// both; and none of [before] (the ids of the step before) is lost, since
/// nothing is taken out of the trash for good here.
void expectPartition(Ledger l, Set<String> before, String reason) {
  final live = [for (final e in l.entries.all) e.id];
  final trash = [for (final t in l.trash.all) t.entry.id];
  expect(live.toSet().length, live.length, reason: '$reason: twice live');
  expect(trash.toSet().length, trash.length, reason: '$reason: twice trash');
  expect(
    live.toSet().intersection(trash.toSet()),
    isEmpty,
    reason: '$reason: live and trashed',
  );
  expect(before.difference(idsOf(l)), isEmpty, reason: '$reason: lost');
}
