import 'package:accounts/accounts.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:drift/drift.dart' show QueryRow, Variable;
import 'package:foundation_values/foundation_values.dart';

import 'adapters.dart';
import 'database.dart';

final class CardInstallmentFact {
  const CardInstallmentFact(this.plan, this.operation);
  final CardInstallmentSchedule plan;
  final OperationId operation;
}

/// Save a plan for one already-posted card purchase. The plan is a projection:
/// it does not create an expense, issuer statement, or payment allocation.
Future<CardInstallmentFact> createCardInstallmentPlan(
  ProbeDatabase db,
  CardInstallmentSchedule plan,
  OperationId operation,
) => db.transaction(() async {
  _requireSchema(db);
  final ws = plan.workspace.id.value;
  final byOperation = await _one(db, 'operation_id', ws, operation.id.value);
  if (byOperation != null) {
    final prior = _decode(byOperation);
    if (const CardInstallmentScheduleCodec().encode(prior.plan) !=
        const CardInstallmentScheduleCodec().encode(plan)) {
      throw const FormatException('Installment operation conflict');
    }
    await _validateLink(db, prior.plan);
    return prior;
  }
  final byPurchase = await _one(
    db,
    'purchase_event_id',
    ws,
    plan.purchaseEventId.value,
  );
  if (byPurchase != null) {
    throw const FormatException('Purchase already has an installment plan');
  }
  await _validateLink(db, plan, requireActive: true);
  if (await _operationUsedElsewhere(db, ws, operation.id.value)) {
    throw const FormatException('Installment operation already used');
  }
  await db.customStatement(
    'INSERT INTO card_installment_plans VALUES (?,?,?,?,?)',
    [
      ws,
      plan.purchaseEventId.value,
      plan.cardId.value,
      operation.id.value,
      const CardInstallmentScheduleCodec().encode(plan),
    ],
  );
  return CardInstallmentFact(plan, operation);
});

Future<List<CardInstallmentFact>> cardInstallmentPlans(
  ProbeDatabase db,
  WorkspaceId workspace,
  PublicId cardId,
) async {
  _requireSchema(db);
  final rows = await db
      .customSelect(
        'SELECT * FROM card_installment_plans WHERE workspace=? AND card_id=? '
        'ORDER BY purchase_event_id',
        variables: [Variable(workspace.id.value), Variable(cardId.value)],
      )
      .get();
  final facts = <CardInstallmentFact>[];
  for (final row in rows) {
    final fact = _decode(row);
    await _validateLink(db, fact.plan);
    facts.add(fact);
  }
  return List.unmodifiable(facts);
}

/// Snapshot capture and restore must call this before publishing a generation.
Future<void> validateCardInstallmentPlans(ProbeDatabase db) async {
  _requireSchema(db);
  final rows = await db
      .customSelect('SELECT * FROM card_installment_plans')
      .get();
  for (final row in rows) {
    final fact = _decode(row);
    await _validateLink(db, fact.plan);
    if (await _operationUsedElsewhere(
      db,
      fact.plan.workspace.id.value,
      fact.operation.id.value,
    )) {
      throw const FormatException('Reused installment operation');
    }
  }
}

void _requireSchema(ProbeDatabase db) {
  if (!db.installmentsAware) {
    throw const FormatException('Installment schema unavailable');
  }
}

Future<QueryRow?> _one(
  ProbeDatabase db,
  String column,
  String ws,
  String id,
) async {
  // Column is supplied only by the two literal call sites above.
  final rows = await db
      .customSelect(
        'SELECT * FROM card_installment_plans WHERE workspace=? AND $column=?',
        variables: [Variable(ws), Variable(id)],
      )
      .get();
  return rows.isEmpty ? null : rows.single;
}

CardInstallmentFact _decode(QueryRow row) {
  final plan = const CardInstallmentScheduleCodec().decode(
    row.read<String>('payload'),
  );
  if (plan.workspace.id.value != row.read<String>('workspace') ||
      plan.purchaseEventId.value != row.read<String>('purchase_event_id') ||
      plan.cardId.value != row.read<String>('card_id')) {
    throw const FormatException('Installment identity mismatch');
  }
  return CardInstallmentFact(
    plan,
    OperationId.parse(row.read<String>('operation_id')),
  );
}

Future<void> _validateLink(
  ProbeDatabase db,
  CardInstallmentSchedule plan, {
  bool requireActive = false,
}) async {
  final ws = plan.workspace.id.value;
  final rows = await db
      .customSelect(
        'SELECT card_id,posted_on,amount_minor FROM card_posted_charges '
        'WHERE workspace=? AND event_id=?',
        variables: [Variable(ws), Variable(plan.purchaseEventId.value)],
      )
      .get();
  if (rows.length != 1 ||
      rows.single.read<String>('card_id') != plan.cardId.value ||
      rows.single.read<int>('amount_minor') !=
          (plan.principal.minorUnits + plan.fixedFee.minorUnits).toInt() ||
      plan.firstScheduledClose.compareTo(
            BusinessDate.parse(rows.single.read<String>('posted_on')),
          ) <
          0) {
    throw const FormatException('Installment purchase mismatch');
  }
  final card = await AccountsAdapter(db).read(plan.workspace, plan.cardId);
  if (card.kind != AccountKind.creditCard ||
      card.currency != plan.principal.currency) {
    throw const FormatException('Installment card mismatch');
  }
  final event = await db
      .customSelect(
        'SELECT kind,business_date,income,expense,currency,scale FROM events '
        'WHERE workspace=? AND id=?',
        variables: [Variable(ws), Variable(plan.purchaseEventId.value)],
      )
      .get();
  final legs = await db
      .customSelect(
        'SELECT account_id,amount,currency,scale,role FROM legs '
        'WHERE workspace=? AND event_id=?',
        variables: [Variable(ws), Variable(plan.purchaseEventId.value)],
      )
      .get();
  final receipts = await db
      .customSelect(
        'SELECT 1 FROM receipts WHERE workspace=? AND result_id=? LIMIT 1',
        variables: [Variable(ws), Variable(plan.purchaseEventId.value)],
      )
      .get();
  final amount = rows.single.read<int>('amount_minor');
  if (event.length != 1 ||
      event.single.read<String>('kind') != 'expense' ||
      event.single.read<int>('income') != 0 ||
      event.single.read<int>('expense') != amount ||
      event.single.read<String>('business_date') !=
          rows.single.read<String>('posted_on') ||
      event.single.read<String>('currency') != card.currency.code ||
      event.single.read<int>('scale') != card.currency.scale ||
      legs.length != 1 ||
      legs.single.read<String>('account_id') != plan.cardId.value ||
      legs.single.read<int>('amount') != -amount ||
      legs.single.read<String>('currency') != card.currency.code ||
      legs.single.read<int>('scale') != card.currency.scale ||
      legs.single.read<String>('role') != 'principal' ||
      receipts.isEmpty) {
    throw const FormatException('Installment Ledger purchase mismatch');
  }
  if (!requireActive) return;
  for (final (table, column) in [
    ('event_refunds', 'original_id'),
    ('event_reversals', 'original_id'),
    ('event_corrections', 'original_id'),
    ('event_tombstones', 'event_id'),
  ]) {
    final invalid = await db
        .customSelect(
          'SELECT 1 FROM $table WHERE workspace=? AND $column=? LIMIT 1',
          variables: [Variable(ws), Variable(plan.purchaseEventId.value)],
        )
        .get();
    if (invalid.isNotEmpty) {
      throw const FormatException('Installment purchase is no longer active');
    }
  }
}

Future<bool> _operationUsedElsewhere(
  ProbeDatabase db,
  String ws,
  String operation,
) async {
  for (final table in [
    'receipts',
    'card_statements',
    'card_payment_allocations',
    'card_authorizations',
    'card_authorization_resolutions',
  ]) {
    final rows = await db
        .customSelect(
          'SELECT 1 FROM $table WHERE workspace=? AND operation_id=? LIMIT 1',
          variables: [Variable(ws), Variable(operation)],
        )
        .get();
    if (rows.isNotEmpty) return true;
  }
  return false;
}
