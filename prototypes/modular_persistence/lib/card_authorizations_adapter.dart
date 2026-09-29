import 'package:accounts/accounts.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:drift/drift.dart';
import 'package:foundation_values/foundation_values.dart';

import 'adapters.dart';
import 'card_revisions_adapter.dart';
import 'database.dart';

enum CardAuthorizationState { pending, cancelled, posted }

final class CardAuthorizationFact {
  const CardAuthorizationFact({
    required this.charge,
    required this.state,
    required this.creationOperation,
    this.resolutionOperation,
  });

  final CardCharge charge;
  final CardAuthorizationState state;
  final OperationId creationOperation;
  final OperationId? resolutionOperation;
}

/// Records an authorization without any Ledger event. The charge ID and
/// operation ID must be retained by the caller across retries.
Future<CardAuthorizationFact> createCardAuthorization(
  ProbeDatabase db,
  CardCharge charge,
  OperationId operation,
) => db.transaction(() async {
  _requireSchema(db);
  if (charge.isPosted || charge.kind != CardChargeKind.purchase) {
    throw const FormatException('Expected a pending card purchase');
  }
  final ws = charge.workspace.id.value;
  final existingOperation = await _authorizationByOperation(db, ws, operation);
  if (existingOperation != null) {
    final prior = await _read(db, existingOperation);
    if (prior.charge.id != charge.id ||
        prior.charge.cardId != charge.cardId ||
        prior.charge.authorizedOn != charge.authorizedOn ||
        prior.charge.authorizedAmount != charge.authorizedAmount) {
      throw const FormatException('Card authorization operation conflict');
    }
    return prior;
  }
  await _requireUnusedOperation(db, ws, operation);
  if (await _authorization(db, ws, charge.id) != null) {
    throw const FormatException('Card charge identity conflict');
  }
  final card = await AccountsAdapter(db).read(charge.workspace, charge.cardId);
  if (card.kind != AccountKind.creditCard ||
      card.state != AccountState.active ||
      !(await currentCardTerms(
        db,
        charge.workspace,
      )).any((terms) => terms.cardId == card.id)) {
    throw const FormatException('Card account is unavailable');
  }
  await db.customStatement(
    'INSERT INTO card_authorizations VALUES (?,?,?,?,?,?,?,?)',
    [
      ws,
      charge.id.value,
      charge.cardId.value,
      charge.authorizedOn.toString(),
      charge.authorizedAmount.currency.code,
      charge.authorizedAmount.currency.scale,
      charge.authorizedAmount.minorUnits.toInt(),
      operation.id.value,
    ],
  );
  return CardAuthorizationFact(
    charge: charge,
    state: CardAuthorizationState.pending,
    creationOperation: operation,
  );
});

Future<CardAuthorizationFact> cancelCardAuthorization(
  ProbeDatabase db,
  WorkspaceId workspace,
  PublicId chargeId,
  OperationId operation,
) => db.transaction(() async {
  _requireSchema(db);
  final ws = workspace.id.value;
  final authorization = await _authorization(db, ws, chargeId);
  if (authorization == null) {
    throw const FormatException('Unknown card authorization');
  }
  final prior = await _resolution(db, ws, chargeId);
  if (prior != null) {
    if (prior.read<String>('state') != 'cancelled' ||
        prior.read<String>('operation_id') != operation.id.value) {
      throw const FormatException('Card authorization already resolved');
    }
    return _read(db, authorization);
  }
  await _requireUnusedOperation(db, ws, operation);
  await db.customStatement(
    'INSERT INTO card_authorization_resolutions VALUES (?,?,?,?,'
    'NULL,NULL,NULL,NULL)',
    [ws, chargeId.value, operation.id.value, 'cancelled'],
  );
  return _read(db, authorization);
});

/// Call inside the same outer transaction as Ledger posting and
/// registerPostedCardCharge. This adapter verifies the committed event and
/// receipt; it does not create a second Ledger event.
Future<CardAuthorizationFact> postCardAuthorization(
  ProbeDatabase db, {
  required WorkspaceId workspace,
  required PublicId chargeId,
  required OperationId operation,
  required PublicId eventId,
  required BusinessDate postedOn,
  required Money settledAmount,
  required Money fee,
}) => db.transaction(() async {
  _requireSchema(db);
  final ws = workspace.id.value;
  final authorization = await _authorization(db, ws, chargeId);
  if (authorization == null) {
    throw const FormatException('Unknown card authorization');
  }
  final fact = await _read(db, authorization);
  // The domain independently validates posting amount and fee.
  fact.charge.post(
    postedOn: postedOn,
    settledAmount: settledAmount,
    fee: fee,
    ledgerEventId: eventId,
  );
  final card = await AccountsAdapter(db).read(workspace, fact.charge.cardId);
  if (settledAmount.currency != card.currency ||
      fee.currency != card.currency) {
    throw const FormatException('Card settlement currency mismatch');
  }
  final prior = await _resolution(db, ws, chargeId);
  if (prior != null) {
    if (prior.read<String>('state') != 'posted' ||
        prior.read<String>('operation_id') != operation.id.value ||
        prior.read<String>('event_id') != eventId.value ||
        prior.read<String>('posted_on') != postedOn.toString() ||
        prior.read<int>('settled_minor') != settledAmount.minorUnits.toInt() ||
        prior.read<int>('fee_minor') != fee.minorUnits.toInt()) {
      throw const FormatException('Card authorization already resolved');
    }
    await _requirePostingLink(
      db,
      ws,
      fact.charge.cardId.value,
      operation,
      eventId,
      postedOn,
      settledAmount + fee,
    );
    return fact;
  }
  await _requireUnusedAuthorizationOperation(db, ws, operation);
  await _requirePostingLink(
    db,
    ws,
    fact.charge.cardId.value,
    operation,
    eventId,
    postedOn,
    settledAmount + fee,
  );
  await db.customStatement(
    'INSERT INTO card_authorization_resolutions VALUES (?,?,?,?,?,?,?,?)',
    [
      ws,
      chargeId.value,
      operation.id.value,
      'posted',
      eventId.value,
      postedOn.toString(),
      settledAmount.minorUnits.toInt(),
      fee.minorUnits.toInt(),
    ],
  );
  return _read(db, authorization);
});

Future<List<CardAuthorizationFact>> cardAuthorizations(
  ProbeDatabase db,
  WorkspaceId workspace,
) async {
  _requireSchema(db);
  final rows = await db
      .customSelect(
        'SELECT * FROM card_authorizations WHERE workspace=? '
        'ORDER BY authorized_on,charge_id',
        variables: [Variable(workspace.id.value)],
      )
      .get();
  return [for (final row in rows) await _read(db, row)];
}

/// Called by the schema-18 card validator during snapshot capture and restore.
Future<void> validateCardAuthorizations(ProbeDatabase db) async {
  _requireSchema(db);
  final rows = await db.customSelect('SELECT * FROM card_authorizations').get();
  final keys = <(String, String)>{};
  final operationKeys = <(String, String)>{};
  for (final row in rows) {
    final ws = row.read<String>('workspace');
    final id = row.read<String>('charge_id');
    keys.add((ws, id));
    final fact = await _read(db, row);
    final card = await AccountsAdapter(db)
        .read(fact.charge.workspace, fact.charge.cardId);
    if (card.kind != AccountKind.creditCard) {
      throw const FormatException('Invalid authorization card');
    }
    if (!operationKeys.add((ws, fact.creationOperation.id.value))) {
      throw const FormatException('Reused card authorization operation');
    }
    if (await _receipt(db, ws, fact.creationOperation) != null) {
      throw const FormatException('Authorization created a Ledger event');
    }
    if (fact.resolutionOperation != null) {
      if (!operationKeys.add((ws, fact.resolutionOperation!.id.value))) {
        throw const FormatException('Reused card authorization operation');
      }
      if (fact.state == CardAuthorizationState.posted) {
        if (fact.charge.settledAmount!.currency != card.currency ||
            fact.charge.fee!.currency != card.currency) {
          throw const FormatException('Invalid posted card currency');
        }
        await _requirePostingLink(
          db,
          ws,
          fact.charge.cardId.value,
          fact.resolutionOperation!,
          fact.charge.ledgerEventId!,
          fact.charge.postedOn!,
          fact.charge.settledAmount! + fact.charge.fee!,
        );
      } else if (await _receipt(db, ws, fact.resolutionOperation!) != null) {
        throw const FormatException('Cancellation created a Ledger event');
      }
    }
  }
  for (final row
      in await db
          .customSelect(
            'SELECT workspace,charge_id FROM card_authorization_resolutions',
          )
          .get()) {
    if (!keys.contains((
      row.read<String>('workspace'),
      row.read<String>('charge_id'),
    ))) {
      throw const FormatException('Orphan card authorization resolution');
    }
  }
}

Future<CardAuthorizationFact> _read(ProbeDatabase db, QueryRow row) async {
  final workspace = WorkspaceId.parse(row.read<String>('workspace'));
  final charge = CardCharge.pending(
    id: PublicId.parse(row.read<String>('charge_id')),
    workspace: workspace,
    cardId: PublicId.parse(row.read<String>('card_id')),
    kind: CardChargeKind.purchase,
    authorizedOn: _date(row.read<String>('authorized_on')),
    authorizedAmount: Money(
      Currency(row.read<String>('currency'), row.read<int>('scale')),
      BigInt.from(row.read<int>('amount_minor')),
    ),
  );
  final operation = OperationId.parse(row.read<String>('operation_id'));
  final resolution = await _resolution(db, workspace.id.value, charge.id);
  if (resolution == null) {
    return CardAuthorizationFact(
      charge: charge,
      state: CardAuthorizationState.pending,
      creationOperation: operation,
    );
  }
  final resolutionOperation = OperationId.parse(
    resolution.read<String>('operation_id'),
  );
  if (resolutionOperation == operation) {
    throw const FormatException('Reused card authorization operation');
  }
  final state = resolution.read<String>('state');
  if (state == 'cancelled') {
    if (resolution.read<String?>('event_id') != null ||
        resolution.read<String?>('posted_on') != null ||
        resolution.read<int?>('settled_minor') != null ||
        resolution.read<int?>('fee_minor') != null) {
      throw const FormatException('Invalid card cancellation');
    }
    return CardAuthorizationFact(
      charge: charge,
      state: CardAuthorizationState.cancelled,
      creationOperation: operation,
      resolutionOperation: resolutionOperation,
    );
  }
  if (state != 'posted') {
    throw const FormatException('Invalid card authorization state');
  }
  final account = await AccountsAdapter(db).read(workspace, charge.cardId);
  final settled = Money(
    account.currency,
    BigInt.from(resolution.read<int>('settled_minor')),
  );
  final fee = Money(
    account.currency,
    BigInt.from(resolution.read<int>('fee_minor')),
  );
  return CardAuthorizationFact(
    charge: charge.post(
      postedOn: _date(resolution.read<String>('posted_on')),
      settledAmount: settled,
      fee: fee,
      ledgerEventId: PublicId.parse(resolution.read<String>('event_id')),
    ),
    state: CardAuthorizationState.posted,
    creationOperation: operation,
    resolutionOperation: resolutionOperation,
  );
}

Future<void> _requirePostingLink(
  ProbeDatabase db,
  String ws,
  String cardId,
  OperationId operation,
  PublicId eventId,
  BusinessDate postedOn,
  Money total,
) async {
  final posted = await db
      .customSelect(
        'SELECT * FROM card_posted_charges WHERE workspace=? AND event_id=?',
        variables: [Variable(ws), Variable(eventId.value)],
      )
      .getSingleOrNull();
  final receipt = await _receipt(db, ws, operation);
  if (posted == null ||
      posted.read<String>('card_id') != cardId ||
      posted.read<String>('posted_on') != postedOn.toString() ||
      posted.read<int>('amount_minor') != total.minorUnits.toInt() ||
      receipt == null ||
      receipt.read<String>('result_id') != eventId.value) {
    throw const FormatException('Card posting does not match Ledger');
  }
}

Future<QueryRow?> _authorization(
  ProbeDatabase db,
  String ws,
  PublicId chargeId,
) => db
    .customSelect(
      'SELECT * FROM card_authorizations WHERE workspace=? AND charge_id=?',
      variables: [Variable(ws), Variable(chargeId.value)],
    )
    .getSingleOrNull();

Future<QueryRow?> _authorizationByOperation(
  ProbeDatabase db,
  String ws,
  OperationId operation,
) => db
    .customSelect(
      'SELECT * FROM card_authorizations WHERE workspace=? AND operation_id=?',
      variables: [Variable(ws), Variable(operation.id.value)],
    )
    .getSingleOrNull();

Future<QueryRow?> _resolution(ProbeDatabase db, String ws, PublicId chargeId) =>
    db
        .customSelect(
          'SELECT * FROM card_authorization_resolutions '
          'WHERE workspace=? AND charge_id=?',
          variables: [Variable(ws), Variable(chargeId.value)],
        )
        .getSingleOrNull();

Future<QueryRow?> _receipt(
  ProbeDatabase db,
  String ws,
  OperationId operation,
) => db
    .customSelect(
      'SELECT * FROM receipts WHERE workspace=? AND operation_id=?',
      variables: [Variable(ws), Variable(operation.id.value)],
    )
    .getSingleOrNull();

Future<void> _requireUnusedAuthorizationOperation(
  ProbeDatabase db,
  String ws,
  OperationId operation,
) async {
  if (await _authorizationByOperation(db, ws, operation) != null ||
      (await db
              .customSelect(
                'SELECT 1 FROM card_authorization_resolutions '
                'WHERE workspace=? AND operation_id=?',
                variables: [Variable(ws), Variable(operation.id.value)],
              )
              .get())
          .isNotEmpty) {
    throw const FormatException('Reused card authorization operation');
  }
}

Future<void> _requireUnusedOperation(
  ProbeDatabase db,
  String ws,
  OperationId operation,
) async {
  await _requireUnusedAuthorizationOperation(db, ws, operation);
  if (await _receipt(db, ws, operation) != null) {
    throw const FormatException('Card operation already used by Ledger');
  }
}

BusinessDate _date(String encoded) {
  final date = BusinessDate.parse(encoded);
  if (date.toString() != encoded) {
    throw const FormatException('Noncanonical card date');
  }
  return date;
}

void _requireSchema(ProbeDatabase db) {
  if (!db.cardAuthorizationsAware) {
    throw UnsupportedError('Card authorizations require schema 19');
  }
}
