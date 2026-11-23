import 'package:ledger_entries/rules.dart';

import '../../models/models.dart';
import '../write_batch.dart' show Collection;
import 'category_refs.dart';
import 'record_json.dart';

/// Reads [row], a record of [collection] as a backup carries it, brought
/// up to this version: a [FormatException] when it cannot be read, or
/// when [shapeIssues] finds it wrong.
void checkRecord(String collection, Map<String, Object?> row) {
  // Out of context, a category's id is as good as its name.
  final refs = CategoryRefs.lenient();
  final issues = shapeIssues(switch (Collection.values
      .asNameMap()[collection]) {
    Collection.account => accountFromJson(row),
    Collection.category => categoryFromJson(row, refs),
    Collection.entry => entryFromJson(row, refs),
    Collection.budget => budgetFromJson(row, refs),
    Collection.recurring => recurringFromJson(row, refs),
    Collection.trash => trashedFromJson(row, refs),
    _ => throw FormatException('Unknown collection $collection'),
  });
  if (issues.isNotEmpty) throw FormatException(issues.join(', '));
}

/// What is wrong with [record], read back from elsewhere such as a
/// backup, that no version of the app would have written and the ledger
/// could not work with: a recurring item every 0 months or on day 40, a
/// card closing on day 0, a negative amount or limit, a transfer to
/// nowhere. The shape rules of package ledger_entries; an old record a
/// newer write rule would refuse, such as an amount of nothing, still
/// reads. None for a record of another kind.
List<RecordIssue> shapeIssues(Object record) => switch (record) {
  Account a => accountShapeIssues(
    closingDay: a.closingDay,
    dueDay: a.dueDay,
    limit: a.limit,
  ),
  Entry e => entryShapeIssues(e),
  Trashed t => entryShapeIssues(t.entry),
  Budget b => budgetIssues(limit: b.limit, warning: b.warning),
  Recurring r => recurringShapeIssues(
    amount: r.amount,
    every: r.every,
    day: r.day,
  ),
  _ => const [],
};
