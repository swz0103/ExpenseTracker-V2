import 'package:accounts/accounts.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:drift/drift.dart';
import 'package:foundation_values/foundation_values.dart';

import 'adapters.dart';
import 'card_authorizations_adapter.dart';
import 'database.dart';

typedef _Key = (String, String);

/// One posted purchase is linked to exactly one existing Ledger expense.
/// Replays with the same identity are harmless; a changed event is not.
Future<void> registerPostedCardCharge(
  ProbeDatabase db,
  WorkspaceId workspace,
  PublicId eventId,
  PublicId cardId,
) => db.transaction(() async {
  _requireSchema(db);
  final ws = workspace.toString();
  final event = await _event(db, ws, eventId.value);
  final legs = await _legs(db, ws, eventId.value);
  final card = await AccountsAdapter(db).read(workspace, cardId);
  if (card.kind != AccountKind.creditCard ||
      event.read<String>('kind') != 'expense' ||
      event.read<int>('income') != 0 ||
      event.read<int>('expense') <= 0 ||
      !_sameCurrency(event, card) ||
      legs.length != 1 ||
      legs.single.read<String>('account_id') != cardId.value ||
      legs.single.read<String>('role') != 'principal' ||
      legs.single.read<int>('amount') != -event.read<int>('expense') ||
      !_sameLegCurrency(legs.single, card)) {
    throw const FormatException('Card purchase does not match Ledger');
  }
  final date = _date(event.read<String>('business_date'));
  await _requireReceipt(db, ws, eventId.value);
  final prior = await _fact(db, 'card_posted_charges', ws, eventId.value);
  if (prior != null) {
    if (prior.read<String>('card_id') != cardId.value ||
        prior.read<String>('posted_on') != date.toString() ||
        prior.read<int>('amount_minor') != event.read<int>('expense')) {
      throw const FormatException('Conflicting card purchase');
    }
    return;
  }
  if (await _fact(db, 'card_payments', ws, eventId.value) != null) {
    throw const FormatException('Card event is already a payment');
  }
  await db.customStatement(
    'INSERT INTO card_posted_charges VALUES (?,?,?,?,?)',
    [
      ws,
      eventId.value,
      cardId.value,
      date.toString(),
      event.read<int>('expense'),
    ],
  );
});

/// The card-side principal is the payment amount. No statement allocation is
/// inferred, so a historical payment remains visible when not yet allocated.
Future<void> registerCardPayment(
  ProbeDatabase db,
  WorkspaceId workspace,
  PublicId eventId,
  PublicId cardId,
) => db.transaction(() async {
  _requireSchema(db);
  final ws = workspace.toString();
  final event = await _event(db, ws, eventId.value);
  final legs = await _legs(db, ws, eventId.value);
  if (event.read<String>('kind') != 'transfer' ||
      event.read<int>('income') != 0 ||
      event.read<int>('expense') != 0 ||
      legs.length != 2 ||
      legs[0].read<String>('role') != 'principal' ||
      legs[1].read<String>('role') != 'principal' ||
      legs[1].read<String>('account_id') != cardId.value ||
      legs[0].read<int>('amount') >= 0 ||
      legs[1].read<int>('amount') != -legs[0].read<int>('amount')) {
    throw const FormatException('Card payment does not match Ledger');
  }
  final source = await AccountsAdapter(db)
      .read(workspace, PublicId.parse(legs[0].read<String>('account_id')));
  final card = await AccountsAdapter(db).read(workspace, cardId);
  if (source.kind != AccountKind.bank ||
      card.kind != AccountKind.creditCard ||
      source.currency != card.currency ||
      !_sameCurrency(event, card) ||
      !_sameLegCurrency(legs[0], card) ||
      !_sameLegCurrency(legs[1], card)) {
    throw const FormatException('Card payment accounts mismatch');
  }
  final date = _date(event.read<String>('business_date'));
  await _requireReceipt(db, ws, eventId.value);
  final prior = await _fact(db, 'card_payments', ws, eventId.value);
  if (prior != null) {
    if (prior.read<String>('card_id') != cardId.value ||
        prior.read<String>('posted_on') != date.toString() ||
        prior.read<int>('amount_minor') != legs[1].read<int>('amount')) {
      throw const FormatException('Conflicting card payment');
    }
    return;
  }
  if (await _fact(db, 'card_posted_charges', ws, eventId.value) != null) {
    throw const FormatException('Card event is already a purchase');
  }
  await db.customStatement('INSERT INTO card_payments VALUES (?,?,?,?,?)', [
    ws,
    eventId.value,
    cardId.value,
    date.toString(),
    legs[1].read<int>('amount'),
  ]);
});

Future<void> appendCardStatementRevision(
  ProbeDatabase db, {
  required WorkspaceId workspace,
  required PublicId statementId,
  required PublicId cardId,
  required int revision,
  required CardCycle cycle,
  required Money billed,
  required OperationId operation,
}) => db.transaction(() async {
  _requireSchema(db);
  final ws = workspace.toString();
  final card = await AccountsAdapter(db).read(workspace, cardId);
  if (revision < 1 ||
      card.kind != AccountKind.creditCard ||
      billed.currency != card.currency ||
      billed.minorUnits < BigInt.zero ||
      billed.minorUnits > BigInt.from(9223372036854775807)) {
    throw const FormatException('Invalid card statement');
  }
  final previousOperation = await db
      .customSelect(
        'SELECT * FROM card_statements WHERE workspace=? AND operation_id=?',
        variables: [
          Variable.withString(ws),
          Variable.withString(operation.id.value),
        ],
      )
      .getSingleOrNull();
  if (previousOperation != null) {
    if (previousOperation.read<String>('statement_id') != statementId.value ||
        previousOperation.read<int>('revision') != revision ||
        previousOperation.read<String>('card_id') != cardId.value ||
        previousOperation.read<String>('starts_after') !=
            cycle.startsAfter.toString() ||
        previousOperation.read<String>('closes_on') !=
            cycle.closesOn.toString() ||
        previousOperation.read<String>('due_on') != cycle.dueOn.toString() ||
        previousOperation.read<int>('billed_minor') !=
            billed.minorUnits.toInt()) {
      throw const FormatException('Conflicting statement operation');
    }
    return;
  }
  final prior = await db
      .customSelect(
        'SELECT * FROM card_statements WHERE workspace=? AND statement_id=? '
        'ORDER BY revision DESC LIMIT 1',
        variables: [
          Variable.withString(ws),
          Variable.withString(statementId.value),
        ],
      )
      .getSingleOrNull();
  if ((prior == null && revision != 1) ||
      (prior != null &&
          (revision != prior.read<int>('revision') + 1 ||
              cardId.value != prior.read<String>('card_id')))) {
    throw const FormatException('Stale statement revision');
  }
  if (prior != null) {
    final allocations = await db
        .customSelect(
          'SELECT 1 FROM card_payment_allocations '
          'WHERE workspace=? AND statement_id=? LIMIT 1',
          variables: [
            Variable.withString(ws),
            Variable.withString(statementId.value),
          ],
        )
        .get();
    if (allocations.isNotEmpty) {
      throw const FormatException('Paid statement cannot be revised');
    }
  }
  await db.customStatement(
    'INSERT INTO card_statements VALUES (?,?,?,?,?,?,?,?,?)',
    [
      ws,
      statementId.value,
      revision,
      cardId.value,
      cycle.startsAfter.toString(),
      cycle.closesOn.toString(),
      cycle.dueOn.toString(),
      billed.minorUnits.toInt(),
      operation.id.value,
    ],
  );
  await validateCardStatementFacts(db);
});

Future<void> allocateCardPayment(
  ProbeDatabase db, {
  required WorkspaceId workspace,
  required PublicId paymentEventId,
  required PublicId statementId,
  required int statementRevision,
  required Money amount,
  required OperationId operation,
}) => db.transaction(() async {
  _requireSchema(db);
  final ws = workspace.toString();
  final payment = await _fact(db, 'card_payments', ws, paymentEventId.value);
  final statement = await db
      .customSelect(
        'SELECT * FROM card_statements WHERE workspace=? AND statement_id=? '
        'AND revision=?',
        variables: [
          Variable.withString(ws),
          Variable.withString(statementId.value),
          Variable.withInt(statementRevision),
        ],
      )
      .getSingleOrNull();
  if (payment == null ||
      statement == null ||
      payment.read<String>('card_id') != statement.read<String>('card_id')) {
    throw const FormatException('Payment or statement unavailable');
  }
  final card = await AccountsAdapter(db)
      .read(workspace, PublicId.parse(payment.read<String>('card_id')));
  if (amount.currency != card.currency ||
      amount.minorUnits <= BigInt.zero ||
      amount.minorUnits > BigInt.from(9223372036854775807)) {
    throw const FormatException('Invalid payment allocation');
  }
  final previous = await db
      .customSelect(
        'SELECT * FROM card_payment_allocations WHERE workspace=? AND operation_id=?',
        variables: [
          Variable.withString(ws),
          Variable.withString(operation.id.value),
        ],
      )
      .getSingleOrNull();
  if (previous != null) {
    if (previous.read<String>('payment_event_id') != paymentEventId.value ||
        previous.read<String>('statement_id') != statementId.value ||
        previous.read<int>('statement_revision') != statementRevision ||
        previous.read<int>('amount_minor') != amount.minorUnits.toInt()) {
      throw const FormatException('Conflicting allocation operation');
    }
    return;
  }
  await db.customStatement(
    'INSERT INTO card_payment_allocations VALUES (?,?,?,?,?,?,?)',
    [
      ws,
      paymentEventId.value,
      statementId.value,
      statementRevision,
      card.id.value,
      amount.minorUnits.toInt(),
      operation.id.value,
    ],
  );
  await validateCardStatementFacts(db);
});

final class ConfirmedCardStatement {
  const ConfirmedCardStatement({
    required this.id,
    required this.cardId,
    required this.revision,
    required this.cycle,
    required this.billed,
    required this.localCharges,
    required this.paid,
    required this.remainingDue,
    required this.refundsAfterClose,
  });
  final PublicId id, cardId;
  final int revision;
  final CardCycle cycle;
  final Money billed, localCharges, paid, remainingDue;
  final List<CardStatementRefundCredit> refundsAfterClose;
}

/// A refund for a purchase in this statement cycle that was posted only after
/// the issuer closed the statement. It remains an independent Ledger event:
/// the confirmed issuer amount and its remaining due are never rewritten.
final class CardStatementRefundCredit {
  const CardStatementRefundCredit({
    required this.eventId,
    required this.originalEventId,
    required this.postedOn,
    required this.amount,
  });

  final PublicId eventId, originalEventId;
  final BusinessDate postedOn;
  final Money amount;
}

final class CardUnallocatedPayment {
  const CardUnallocatedPayment({
    required this.eventId,
    required this.cardId,
    required this.postedOn,
    required this.total,
    required this.unallocated,
  });
  final PublicId eventId, cardId;
  final BusinessDate postedOn;
  final Money total, unallocated;
}

/// Statement due is a read model. A historical transfer with no allocation
/// remains in [unallocatedCardPayments], not silently assigned to a cycle.
Future<List<ConfirmedCardStatement>> confirmedCardStatements(
  ProbeDatabase db,
  WorkspaceId workspace,
  PublicId cardId,
) async {
  _requireSchema(db);
  await validateCardStatementFacts(db);
  final card = await AccountsAdapter(db).read(workspace, cardId);
  if (card.kind != AccountKind.creditCard) {
    throw const FormatException('Not a card account');
  }
  final ws = workspace.toString();
  final statements = await db
      .customSelect(
        'SELECT s.* FROM card_statements s JOIN '
        '(SELECT workspace,statement_id,MAX(revision) AS latest '
        'FROM card_statements GROUP BY workspace,statement_id) v '
        'ON v.workspace=s.workspace AND v.statement_id=s.statement_id '
        'AND v.latest=s.revision WHERE s.workspace=? AND s.card_id=? '
        'ORDER BY s.closes_on,s.statement_id',
        variables: [Variable.withString(ws), Variable.withString(cardId.value)],
      )
      .get();
  final charges = await db
      .customSelect(
        'SELECT posted_on,amount_minor FROM card_posted_charges '
        'WHERE workspace=? AND card_id=?',
        variables: [Variable.withString(ws), Variable.withString(cardId.value)],
      )
      .get();
  final allocations = await db
      .customSelect(
        'SELECT statement_id,amount_minor FROM card_payment_allocations '
        'WHERE workspace=? AND card_id=?',
        variables: [Variable.withString(ws), Variable.withString(cardId.value)],
      )
      .get();
  final refunds = await db
      .customSelect(
        'SELECT r.event_id,r.original_id,e.business_date,e.expense,'
        'c.posted_on FROM event_refunds r '
        'JOIN events e ON e.workspace=r.workspace AND e.id=r.event_id '
        'JOIN card_posted_charges c ON c.workspace=r.workspace '
        'AND c.event_id=r.original_id '
        'WHERE r.workspace=? AND c.card_id=? '
        'ORDER BY e.business_date,r.event_id',
        variables: [Variable.withString(ws), Variable.withString(cardId.value)],
      )
      .get();
  return List.unmodifiable([
    for (final row in statements)
      () {
        final cycle = CardCycle(
          startsAfter: _date(row.read<String>('starts_after')),
          closesOn: _date(row.read<String>('closes_on')),
          dueOn: _date(row.read<String>('due_on')),
        );
        final id = PublicId.parse(row.read<String>('statement_id'));
        final localChargesMinor = charges.fold<BigInt>(
          BigInt.zero,
          (sum, charge) =>
              sum +
              (cycle.includes(_date(charge.read<String>('posted_on')))
                  ? BigInt.from(charge.read<int>('amount_minor'))
                  : BigInt.zero),
        );
        final paidMinor = allocations.fold<BigInt>(
          BigInt.zero,
          (sum, allocation) =>
              sum +
              (allocation.read<String>('statement_id') == id.value
                  ? BigInt.from(allocation.read<int>('amount_minor'))
                  : BigInt.zero),
        );
        return ConfirmedCardStatement(
          id: id,
          cardId: cardId,
          revision: row.read<int>('revision'),
          cycle: cycle,
          billed: Money(
            card.currency,
            BigInt.from(row.read<int>('billed_minor')),
          ),
          localCharges: Money(card.currency, localChargesMinor),
          paid: Money(card.currency, paidMinor),
          remainingDue: Money(
            card.currency,
            BigInt.from(row.read<int>('billed_minor')) - paidMinor,
          ),
          refundsAfterClose: List.unmodifiable([
            for (final refund in refunds)
              if (cycle.includes(_date(refund.read<String>('posted_on'))) &&
                  _date(refund.read<String>('business_date'))
                          .compareTo(cycle.closesOn) >
                      0)
                CardStatementRefundCredit(
                  eventId: PublicId.parse(refund.read<String>('event_id')),
                  originalEventId: PublicId.parse(
                    refund.read<String>('original_id'),
                  ),
                  postedOn: _date(refund.read<String>('business_date')),
                  amount: Money(
                    card.currency,
                    -BigInt.from(refund.read<int>('expense')),
                  ),
                ),
          ]),
        );
      }(),
  ]);
}

Future<List<CardUnallocatedPayment>> unallocatedCardPayments(
  ProbeDatabase db,
  WorkspaceId workspace,
  PublicId cardId,
) async {
  _requireSchema(db);
  await validateCardStatementFacts(db);
  final card = await AccountsAdapter(db).read(workspace, cardId);
  if (card.kind != AccountKind.creditCard) {
    throw const FormatException('Not a card account');
  }
  final payments = await db
      .customSelect(
        'SELECT event_id,posted_on,amount_minor FROM card_payments '
        'WHERE workspace=? AND card_id=? ORDER BY posted_on,event_id',
        variables: [
          Variable.withString(workspace.toString()),
          Variable.withString(cardId.value),
        ],
      )
      .get();
  final allocationRows = await db
      .customSelect(
        'SELECT payment_event_id,amount_minor FROM card_payment_allocations '
        'WHERE workspace=? AND card_id=?',
        variables: [
          Variable.withString(workspace.toString()),
          Variable.withString(cardId.value),
        ],
      )
      .get();
  final allocated = <String, BigInt>{};
  for (final row in allocationRows) {
    final id = row.read<String>('payment_event_id');
    allocated[id] =
        (allocated[id] ?? BigInt.zero) +
        BigInt.from(row.read<int>('amount_minor'));
  }
  return List.unmodifiable([
    for (final row in payments)
      if (BigInt.from(row.read<int>('amount_minor')) >
          (allocated[row.read<String>('event_id')] ?? BigInt.zero))
        CardUnallocatedPayment(
          eventId: PublicId.parse(row.read<String>('event_id')),
          cardId: cardId,
          postedOn: _date(row.read<String>('posted_on')),
          total: Money(
            card.currency,
            BigInt.from(row.read<int>('amount_minor')),
          ),
          unallocated: Money(
            card.currency,
            BigInt.from(row.read<int>('amount_minor')) -
                (allocated[row.read<String>('event_id')] ?? BigInt.zero),
          ),
        ),
  ]);
}

/// Validates the whole authority set, including every Ledger event touching a
/// card. Call during snapshot capture and staged restore, as well as writes.
Future<void> validateCardStatementFacts(ProbeDatabase db) async {
  _requireSchema(db);
  final accountRows = await db
      .customSelect('SELECT workspace,id FROM accounts')
      .get();
  final accounts = <_Key, Account>{};
  for (final row in accountRows) {
    final ws = row.read<String>('workspace');
    final id = row.read<String>('id');
    accounts[(ws, id)] = await AccountsAdapter(db)
        .read(WorkspaceId.parse(ws), PublicId.parse(id));
  }
  final eventRows = await db.customSelect('SELECT * FROM events').get();
  final events = <_Key, QueryRow>{
    for (final row in eventRows)
      (row.read<String>('workspace'), row.read<String>('id')): row,
  };
  final legsByEvent = <_Key, List<QueryRow>>{};
  for (final row
      in await db
          .customSelect(
            'SELECT * FROM legs ORDER BY workspace,event_id,ordinal',
          )
          .get()) {
    (legsByEvent[(
              row.read<String>('workspace'),
              row.read<String>('event_id'),
            )] ??=
            [])
        .add(row);
  }
  final charges = <_Key, QueryRow>{};
  for (final row
      in await db.customSelect('SELECT * FROM card_posted_charges').get()) {
    charges[(row.read<String>('workspace'), row.read<String>('event_id'))] =
        row;
  }
  final payments = <_Key, QueryRow>{};
  for (final row
      in await db.customSelect('SELECT * FROM card_payments').get()) {
    payments[(row.read<String>('workspace'), row.read<String>('event_id'))] =
        row;
  }
  final refundSources = <_Key, String>{};
  if (db.cardAuthorizationsAware) {
    for (final row
        in await db.customSelect('SELECT * FROM event_refunds').get()) {
      refundSources[(
        row.read<String>('workspace'),
        row.read<String>('event_id'),
      )] = row.read<String>(
        'original_id',
      );
    }
  }
  final refundedByPurchase = <_Key, BigInt>{};
  final cardKeys = <_Key>{};
  for (final entry in events.entries) {
    final event = entry.value;
    final ws = entry.key.$1;
    final legs = legsByEvent[entry.key] ?? const <QueryRow>[];
    final cardLegs = legs
        .where(
          (leg) =>
              accounts[(ws, leg.read<String>('account_id'))]?.kind ==
              AccountKind.creditCard,
        )
        .toList();
    if (cardLegs.isEmpty) continue;
    cardKeys.add(entry.key);
    final charge = charges[entry.key];
    final payment = payments[entry.key];
    final kind = event.read<String>('kind');
    if (kind == 'opening') {
      if (legs.length != 1 ||
          cardLegs.length != 1 ||
          legs.single.read<int>('amount') != 0 ||
          event.read<int>('income') != 0 ||
          event.read<int>('expense') != 0 ||
          charge != null ||
          payment != null) {
        throw const FormatException('Invalid card opening');
      }
      continue;
    }
    if (kind == 'expense') {
      if (charge == null ||
          payment != null ||
          legs.length != 1 ||
          cardLegs.length != 1 ||
          event.read<int>('income') != 0 ||
          event.read<int>('expense') <= 0 ||
          legs.single.read<String>('role') != 'principal' ||
          legs.single.read<int>('amount') != -event.read<int>('expense') ||
          charge.read<String>('card_id') !=
              legs.single.read<String>('account_id') ||
          charge.read<int>('amount_minor') != event.read<int>('expense') ||
          charge.read<String>('posted_on') !=
              _date(event.read<String>('business_date')).toString() ||
          !_sameCurrency(
            event,
            accounts[(ws, charge.read<String>('card_id'))]!,
          ) ||
          !_sameLegCurrency(
            legs.single,
            accounts[(ws, charge.read<String>('card_id'))]!,
          )) {
        throw const FormatException('Invalid posted card charge');
      }
    } else if (kind == 'refund' && db.cardAuthorizationsAware) {
      final originalId = refundSources[entry.key];
      final original = originalId == null ? null : charges[(ws, originalId)];
      final card = cardLegs.length == 1
          ? accounts[(ws, cardLegs.single.read<String>('account_id'))]
          : null;
      final returned = -BigInt.from(event.read<int>('expense'));
      if (charge != null ||
          payment != null ||
          original == null ||
          card == null ||
          legs.length != 1 ||
          cardLegs.length != 1 ||
          event.read<int>('income') != 0 ||
          returned <= BigInt.zero ||
          legs.single.read<String>('role') != 'principal' ||
          BigInt.from(legs.single.read<int>('amount')) != returned ||
          original.read<String>('card_id') != card.id.value ||
          !_sameCurrency(event, card) ||
          !_sameLegCurrency(legs.single, card) ||
          _date(event.read<String>('business_date'))
                  .compareTo(_date(original.read<String>('posted_on'))) <
              0) {
        throw const FormatException('Invalid posted card refund');
      }
      final originalKey = (ws, originalId!);
      final total = (refundedByPurchase[originalKey] ?? BigInt.zero) + returned;
      if (total > BigInt.from(original.read<int>('amount_minor'))) {
        throw const FormatException('Card refunds exceed purchase');
      }
      refundedByPurchase[originalKey] = total;
    } else if (kind == 'transfer') {
      if (payment == null ||
          charge != null ||
          legs.length != 2 ||
          cardLegs.length != 1 ||
          event.read<int>('income') != 0 ||
          event.read<int>('expense') != 0 ||
          accounts[(ws, legs[0].read<String>('account_id'))]?.kind !=
              AccountKind.bank ||
          legs[1].read<String>('account_id') !=
              cardLegs.single.read<String>('account_id') ||
          legs[0].read<String>('role') != 'principal' ||
          legs[1].read<String>('role') != 'principal' ||
          legs[0].read<int>('amount') >= 0 ||
          legs[1].read<int>('amount') != -legs[0].read<int>('amount') ||
          payment.read<String>('card_id') !=
              legs[1].read<String>('account_id') ||
          payment.read<int>('amount_minor') != legs[1].read<int>('amount') ||
          payment.read<String>('posted_on') !=
              _date(event.read<String>('business_date')).toString()) {
        throw const FormatException('Invalid card payment');
      }
      final source = accounts[(ws, legs[0].read<String>('account_id'))]!;
      final card = accounts[(ws, payment.read<String>('card_id'))]!;
      if (source.currency != card.currency ||
          !_sameCurrency(event, card) ||
          !_sameLegCurrency(legs[0], card) ||
          !_sameLegCurrency(legs[1], card)) {
        throw const FormatException('Card payment currency mismatch');
      }
    } else {
      throw const FormatException('Unsupported card Ledger event');
    }
    await _requireReceipt(db, ws, entry.key.$2);
  }
  if (db.cardAuthorizationsAware) {
    for (final entry in refundSources.entries) {
      if (charges.containsKey((entry.key.$1, entry.value)) &&
          !cardKeys.contains(entry.key)) {
        throw const FormatException('Card purchase refunded outside its card');
      }
    }
  }
  if (charges.keys.any((key) => !cardKeys.contains(key)) ||
      payments.keys.any((key) => !cardKeys.contains(key))) {
    throw const FormatException('Orphan card fact');
  }
  if (db.tombstonesAware) {
    for (final row
        in await db
            .customSelect('SELECT workspace,event_id FROM event_tombstones')
            .get()) {
      if (cardKeys.contains((
        row.read<String>('workspace'),
        row.read<String>('event_id'),
      ))) {
        throw const FormatException('Tombstoned card event');
      }
    }
  }
  if (db.correctionsAware) {
    for (final row
        in await db
            .customSelect(
              'SELECT workspace,original_id,reversal_id,replacement_id FROM event_corrections',
            )
            .get()) {
      final ws = row.read<String>('workspace');
      if ([
        row.read<String>('original_id'),
        row.read<String>('reversal_id'),
        row.read<String>('replacement_id'),
      ].any((id) => cardKeys.contains((ws, id)))) {
        throw const FormatException('Corrected card event');
      }
    }
  }
  final latestStatements = <_Key, QueryRow>{};
  final expectedRevision = <_Key, int>{};
  final statementRows = await db
      .customSelect(
        'SELECT * FROM card_statements ORDER BY workspace,statement_id,revision',
      )
      .get();
  for (final row in statementRows) {
    final ws = row.read<String>('workspace');
    final id = row.read<String>('statement_id');
    PublicId.parse(id);
    OperationId.parse(row.read<String>('operation_id'));
    final key = (ws, id);
    final revision = row.read<int>('revision');
    final cardId = row.read<String>('card_id');
    final account = accounts[(ws, cardId)];
    final cycle = CardCycle(
      startsAfter: _date(row.read<String>('starts_after')),
      closesOn: _date(row.read<String>('closes_on')),
      dueOn: _date(row.read<String>('due_on')),
    );
    if (account?.kind != AccountKind.creditCard ||
        row.read<int>('billed_minor') < 0 ||
        revision != (expectedRevision[key] ?? 0) + 1 ||
        (latestStatements[key] != null &&
            latestStatements[key]!.read<String>('card_id') != cardId) ||
        cycle.closesOn.compareTo(account!.openedOn) < 0) {
      throw const FormatException('Invalid statement revision');
    }
    expectedRevision[key] = revision;
    latestStatements[key] = row;
  }
  final active = latestStatements.values.toList();
  for (var i = 0; i < active.length; i++) {
    final a = active[i];
    final aCycle = CardCycle(
      startsAfter: _date(a.read<String>('starts_after')),
      closesOn: _date(a.read<String>('closes_on')),
      dueOn: _date(a.read<String>('due_on')),
    );
    for (var j = i + 1; j < active.length; j++) {
      final b = active[j];
      if (a.read<String>('workspace') == b.read<String>('workspace') &&
          a.read<String>('card_id') == b.read<String>('card_id')) {
        final bCycle = CardCycle(
          startsAfter: _date(b.read<String>('starts_after')),
          closesOn: _date(b.read<String>('closes_on')),
          dueOn: _date(b.read<String>('due_on')),
        );
        if (aCycle.startsAfter.compareTo(bCycle.closesOn) < 0 &&
            bCycle.startsAfter.compareTo(aCycle.closesOn) < 0) {
          throw const FormatException('Overlapping card statements');
        }
      }
    }
  }
  final paymentTotals = <_Key, BigInt>{};
  final statementTotals = <_Key, BigInt>{};
  for (final row
      in await db
          .customSelect('SELECT * FROM card_payment_allocations')
          .get()) {
    final ws = row.read<String>('workspace');
    final paymentId = row.read<String>('payment_event_id');
    final statementId = row.read<String>('statement_id');
    final key = (ws, paymentId);
    final statementKey = (ws, statementId);
    final payment = payments[key];
    final statement = latestStatements[statementKey];
    final amount = row.read<int>('amount_minor');
    OperationId.parse(row.read<String>('operation_id'));
    if (payment == null ||
        statement == null ||
        amount <= 0 ||
        statement.read<int>('revision') !=
            row.read<int>('statement_revision') ||
        payment.read<String>('card_id') != row.read<String>('card_id') ||
        statement.read<String>('card_id') != row.read<String>('card_id')) {
      throw const FormatException('Invalid card payment allocation');
    }
    paymentTotals[key] =
        (paymentTotals[key] ?? BigInt.zero) + BigInt.from(amount);
    statementTotals[statementKey] =
        (statementTotals[statementKey] ?? BigInt.zero) + BigInt.from(amount);
    if (paymentTotals[key]! > BigInt.from(payment.read<int>('amount_minor'))) {
      throw const FormatException('Overallocated card payment');
    }
  }
  for (final entry in statementTotals.entries) {
    final statement = latestStatements[entry.key]!;
    if (entry.value > BigInt.from(statement.read<int>('billed_minor'))) {
      throw const FormatException('Payment exceeds issuer statement total');
    }
  }
  if (db.cardAuthorizationsAware) {
    await validateCardAuthorizations(db);
  }
}

void _requireSchema(ProbeDatabase db) {
  if (!db.cardStatementsAware) {
    throw UnsupportedError('Card facts require schema 18');
  }
}

BusinessDate _date(String text) {
  final date = BusinessDate.parse(text);
  if (date.toString() != text)
    throw const FormatException('Noncanonical card date');
  return date;
}

bool _sameCurrency(QueryRow event, Account account) =>
    event.read<String>('currency') == account.currency.code &&
    event.read<int>('scale') == account.currency.scale;

bool _sameLegCurrency(QueryRow leg, Account account) =>
    leg.read<String>('currency') == account.currency.code &&
    leg.read<int>('scale') == account.currency.scale;

Future<QueryRow> _event(ProbeDatabase db, String ws, String id) async =>
    await db
        .customSelect(
          'SELECT * FROM events WHERE workspace=? AND id=?',
          variables: [Variable.withString(ws), Variable.withString(id)],
        )
        .getSingleOrNull() ??
    (throw const FormatException('Missing Ledger event'));

Future<List<QueryRow>> _legs(ProbeDatabase db, String ws, String id) => db
    .customSelect(
      'SELECT * FROM legs WHERE workspace=? AND event_id=? ORDER BY ordinal',
      variables: [Variable.withString(ws), Variable.withString(id)],
    )
    .get();

Future<QueryRow?> _fact(ProbeDatabase db, String table, String ws, String id) =>
    db
        .customSelect(
          'SELECT * FROM $table WHERE workspace=? AND event_id=?',
          variables: [Variable.withString(ws), Variable.withString(id)],
        )
        .getSingleOrNull();

Future<void> _requireReceipt(
  ProbeDatabase db,
  String ws,
  String eventId,
) async {
  // Notes and other metadata commands share the event ID as result_id; only
  // the financial posting receipt counts (same rule as validated_restore).
  final receipts = await db
      .customSelect(
        '''SELECT r.operation_id FROM receipts r JOIN audit a
        ON a.workspace=r.workspace AND a.operation_id=r.operation_id
        WHERE r.workspace=? AND r.result_id=?
        AND a.kind NOT LIKE 'category.%' AND a.kind NOT LIKE 'tag.%'
        AND a.kind NOT LIKE 'merchant.%' AND a.kind!='ledger.note'
        AND a.kind!='ledger.tombstone' ''',
        variables: [Variable.withString(ws), Variable.withString(eventId)],
      )
      .get();
  if (receipts.length != 1) {
    throw const FormatException('Card event receipt mismatch');
  }
}
