import 'package:accounts/accounts.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:drift/drift.dart';
import 'package:foundation_values/foundation_values.dart';

import 'adapters.dart';
import 'database.dart';

final class CardTermsRevision {
  const CardTermsRevision(
    this.terms,
    this.operation,
    this.recordedAt,
    this.disabled,
  );

  final CreditCardTerms terms;
  final OperationId operation;
  final DateTime recordedAt;
  final bool disabled;
}

Future<CardTermsRevision> appendCardTermsRevision(
  ProbeDatabase db,
  CreditCardTerms terms,
  OperationId operation,
  DateTime recordedAt, {
  bool disabled = false,
}) async {
  if (!db.creditCardsAware)
    throw UnsupportedError('Credit cards require schema 17');
  if (!recordedAt.isUtc)
    throw const FormatException('Card audit time must be UTC');
  final payload = const CreditCardTermsCodec().encode(terms);
  return db.transaction(() async {
    final account = await AccountsAdapter(db)
        .read(terms.workspace, terms.cardId);
    if (account.kind != AccountKind.creditCard ||
        account.currency != terms.currency ||
        account.state != AccountState.active) {
      throw const FormatException('Card account is unavailable');
    }
    final priorOperation = await db
        .customSelect(
          'SELECT * FROM card_revisions WHERE workspace=? AND operation_id=?',
          variables: [
            Variable(terms.workspace.id.value),
            Variable(operation.id.value),
          ],
        )
        .getSingleOrNull();
    if (priorOperation != null) {
      final previous = _read(priorOperation.data);
      if (previous.terms.cardId != terms.cardId ||
          const CreditCardTermsCodec().encode(previous.terms) != payload ||
          previous.disabled != disabled) {
        throw const FormatException('Card operation conflict');
      }
      return previous;
    }
    final latest = await db
        .customSelect(
          'SELECT * FROM card_revisions WHERE workspace=? AND card_id=? '
          'ORDER BY version DESC LIMIT 1',
          variables: [
            Variable(terms.workspace.id.value),
            Variable(terms.cardId.value),
          ],
        )
        .getSingleOrNull();
    if (latest == null) {
      if (terms.version != 1 || disabled) {
        throw const FormatException('Invalid first card revision');
      }
    } else {
      final previous = _read(latest.data);
      if (previous.disabled || terms.version != previous.terms.version + 1) {
        throw const FormatException('Stale or disabled card');
      }
      if (disabled &&
          const CreditCardTermsCodec().encode(
                _withVersion(previous.terms, terms.version),
              ) !=
              payload) {
        throw const FormatException('Disabling cannot change card settings');
      }
    }
    await db.customStatement(
      'INSERT INTO card_revisions '
      '(workspace,card_id,version,operation_id,recorded_at,state,payload) '
      'VALUES (?,?,?,?,?,?,?)',
      [
        terms.workspace.id.value,
        terms.cardId.value,
        terms.version,
        operation.id.value,
        recordedAt.toIso8601String(),
        disabled ? 'disabled' : 'active',
        payload,
      ],
    );
    return CardTermsRevision(terms, operation, recordedAt, disabled);
  });
}

Future<List<CardTermsRevision>> cardTermsHistory(
  ProbeDatabase db,
  WorkspaceId workspace,
) async {
  if (!db.creditCardsAware)
    throw UnsupportedError('Credit cards require schema 17');
  final rows = await db
      .customSelect(
        'SELECT * FROM card_revisions WHERE workspace=? ORDER BY card_id,version',
        variables: [Variable(workspace.id.value)],
      )
      .get();
  return [for (final row in rows) _read(row.data)];
}

Future<List<CreditCardTerms>> currentCardTerms(
  ProbeDatabase db,
  WorkspaceId workspace,
) async {
  final latest = <PublicId, CardTermsRevision>{};
  for (final revision in await cardTermsHistory(db, workspace)) {
    latest[revision.terms.cardId] = revision;
  }
  return [
    for (final revision in latest.values)
      if (!revision.disabled) revision.terms,
  ];
}

Future<void> validateCardTermsRevisions(ProbeDatabase db) async {
  if (!db.creditCardsAware)
    throw UnsupportedError('Credit cards require schema 17');
  final rows = await db
      .customSelect(
        'SELECT * FROM card_revisions ORDER BY workspace,card_id,version',
      )
      .get();
  CardTermsRevision? previous;
  for (final row in rows) {
    final revision = _read(row.data);
    final account = await AccountsAdapter(db)
        .read(revision.terms.workspace, revision.terms.cardId);
    if (account.kind != AccountKind.creditCard ||
        account.currency != revision.terms.currency) {
      throw const FormatException('Card account mismatch');
    }
    final sameCard =
        previous != null &&
        previous.terms.workspace == revision.terms.workspace &&
        previous.terms.cardId == revision.terms.cardId;
    if (!sameCard) {
      if (revision.terms.version != 1 || revision.disabled) {
        throw const FormatException('Invalid first card revision');
      }
    } else if (previous.disabled ||
        revision.terms.version != previous.terms.version + 1 ||
        (revision.disabled &&
            const CreditCardTermsCodec().encode(
                  _withVersion(previous.terms, revision.terms.version),
                ) !=
                const CreditCardTermsCodec().encode(revision.terms))) {
      throw const FormatException('Invalid card revision sequence');
    }
    previous = revision;
  }
  final cardAccounts = await db
      .customSelect('SELECT workspace,id,payload FROM accounts')
      .get();
  final cardsWithTerms = <(String, String)>{
    for (final row in rows)
      (row.read<String>('workspace'), row.read<String>('card_id')),
  };
  for (final row in cardAccounts) {
    final account = await AccountsAdapter(db).read(
      WorkspaceId.parse(row.read<String>('workspace')),
      PublicId.parse(row.read<String>('id')),
    );
    if (account.kind == AccountKind.creditCard &&
        !cardsWithTerms.contains((
          account.workspace.id.value,
          account.id.value,
        ))) {
      throw const FormatException('Card account has no saved settings');
    }
  }
}

CardTermsRevision _read(Map<String, Object?> row) {
  final terms = const CreditCardTermsCodec().decode(row['payload'] as String);
  if (terms.workspace.id.value != row['workspace'] ||
      terms.cardId.value != row['card_id'] ||
      terms.version != row['version']) {
    throw const FormatException('Card revision identity mismatch');
  }
  final timestamp = DateTime.parse(row['recorded_at'] as String);
  if (!timestamp.isUtc || timestamp.toIso8601String() != row['recorded_at']) {
    throw const FormatException('Invalid card audit time');
  }
  final state = row['state'];
  if (state != 'active' && state != 'disabled') {
    throw const FormatException('Invalid card revision state');
  }
  return CardTermsRevision(
    terms,
    OperationId.parse(row['operation_id'] as String),
    timestamp,
    state == 'disabled',
  );
}

CreditCardTerms _withVersion(CreditCardTerms terms, int version) =>
    CreditCardTerms(
      workspace: terms.workspace,
      cardId: terms.cardId,
      currency: terms.currency,
      closingDay: terms.closingDay,
      dueDay: terms.dueDay,
      limit: terms.limit,
      version: version,
    );
