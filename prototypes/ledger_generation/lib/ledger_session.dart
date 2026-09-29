part of 'ledger_store.dart';

final class SessionClosed implements Exception {}

final class PreviewCapacity implements Exception {}

final class AccountSummary {
  const AccountSummary(this.account, this.balance);
  final Account account;
  final Money balance;
}

final class LedgerEntry {
  const LedgerEntry(
    this.id,
    this.date,
    this.kind,
    this.accountId,
    this.amount, {
    this.destinationId,
    this.received,
    this.fee,
    this.refundOf,
    this.refunded,
    this.reversalOf,
    this.reversedBy,
    this.correctedBy,
    this.reversalReason,
    this.tombstoneReason,
    this.note = const EntryNote(0, ''),
  });
  final PublicId id;
  final BusinessDate date;
  final PostingKind kind;
  final PublicId accountId;
  final Money amount;

  /// Transfer amount is the signed source principal; fee is separate.
  final PublicId? destinationId;
  final Money? received;
  final Money? fee;
  final PublicId? refundOf;
  final Money? refunded;
  final PublicId? reversalOf, reversedBy;
  final PublicId? correctedBy;
  final String? reversalReason;
  final String? tombstoneReason;
  final EntryNote note;
}

/// Exclusive, bounded command scope. No public SQL or database handle.
/// Preview limits preserve room for portable backups; not full M3 capacity.
final class LedgerSession {
  LedgerSession._(this._db);
  static const maxEvents = 5000;
  static const maxNoteChanges = 5000;
  static const maxAccounts = 32;
  static const maxCategories = 256;
  static const maxCategoryChanges = 1024;
  static const maxMerchants = 256;
  static const maxMerchantChanges = 1024;
  static const maxTags = 256;
  static const maxTagChanges = 1024;
  static const maxBudgetChanges = 1024;
  static const maxRecurringChanges = 1024;
  static const maxCardChanges = 1024;
  final ProbeDatabase _db;
  Future<void> _tail = Future.value();
  bool _closed = false;
  ({int rows, int bytes})? _capacityUsage;

  Future<T> _write<T>(Future<T> Function() work) async {
    final prior = _capacityUsage;
    try {
      return await _db.transaction(work);
    } catch (_) {
      // Admission and deltas must roll back with SQLite, including failed commit.
      _capacityUsage = prior;
      rethrow;
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() work) {
    if (_closed) return Future.error(SessionClosed());
    final result = _tail.then((_) => work());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _close() async {
    _closed = true;
    await _tail;
  }

  Future<int> _count(String table) async =>
      (await _db.customSelect('SELECT count(*) AS n FROM $table').getSingle())
          .read<int>('n');

  Future<bool> _hasOperation(OperationKey operation) async {
    final prior = await _db
        .customSelect(
          'SELECT operation_id FROM receipts WHERE workspace=? AND operation_id=?',
          variables: [
            Variable.withString(operation.workspace.toString()),
            Variable.withString(operation.operation.toString()),
          ],
        )
        .get();
    return prior.isNotEmpty;
  }

  Future<void> _admitCapacity() async {
    if (_capacityUsage != null) return;
    final admitted = validateSessionCapacity(
      await SnapshotCodec(
        categoryAware: _db.categoryAware,
        generationAware: true,
        categoryReferences: _db.categoryReferences,
        tagsAware: _db.tagsAware,
        merchantsAware: _db.merchantsAware,
        transfersAware: _db.transfersAware,
        fxTransfersAware: _db.fxTransfersAware,
        refundsAware: _db.refundsAware,
        reversalsAware: _db.reversalsAware,
        notesAware: _db.notesAware,
        correctionsAware: _db.correctionsAware,
        tombstonesAware: _db.tombstonesAware,
        budgetsAware: _db.budgetsAware,
        recurringAware: _db.recurringAware,
        creditCardsAware: _db.creditCardsAware,
        cardStatementsAware: _db.cardStatementsAware,
      ).capture(_db),
      categoryAware: _db.categoryAware,
      categoryReferences: _db.categoryReferences,
      tagsAware: _db.tagsAware,
      merchantsAware: _db.merchantsAware,
      transfersAware: _db.transfersAware,
      fxTransfersAware: _db.fxTransfersAware,
      refundsAware: _db.refundsAware,
      reversalsAware: _db.reversalsAware,
      notesAware: _db.notesAware,
      correctionsAware: _db.correctionsAware,
      tombstonesAware: _db.tombstonesAware,
      budgetsAware: _db.budgetsAware,
      recurringAware: _db.recurringAware,
      creditCardsAware: _db.creditCardsAware,
      cardStatementsAware: _db.cardStatementsAware,
    );
    _capacityUsage = _snapshotUsage(admitted);
  }

  Future<void> _capacity(Posting posting, {bool account = false}) async {
    // Replays and conflicts must retain their original meaning at capacity.
    if (await _hasOperation(posting.operation)) return;
    await _admitCapacity();
    if (await _count('events') >= maxEvents ||
        (account && await _count('accounts') >= maxAccounts)) {
      throw PreviewCapacity();
    }
  }

  Future<CommitResult> createAccount(
    Account account,
    Posting opening, {
    CreditCardTerms? cardTerms,
  }) => _enqueue(
    () => _write(() async {
      if (_db.cardStatementsAware &&
          account.kind == AccountKind.creditCard &&
          opening.legs.single.amount.minorUnits != BigInt.zero) {
        throw const CreditCardException(CreditCardError.invalidInput);
      }
      await _capacity(opening, account: true);
      final result = await FinancialWorkflows(
        _db,
        sourceContext: 'preview-manual-v1',
      ).createAccount(account, opening, cardTerms: cardTerms);
      if (!result.replayed)
        await _checkFinancialRows(opening, account: account);
      if (!result.replayed && cardTerms != null) {
        await _checkRows('card_revisions', 'workspace=? AND card_id=?', [
          account.workspace.id.value,
          account.id.value,
        ]);
      }
      return result;
    }),
  );

  Future<List<CreditCardTerms>> creditCardTerms(WorkspaceId workspace) =>
      _enqueue(() => currentCardTerms(_db, workspace));

  Future<void> confirmCardStatement({
    required WorkspaceId workspace,
    required PublicId statementId,
    required PublicId cardId,
    required int revision,
    required CardCycle cycle,
    required Money billed,
    required OperationId operation,
  }) => _enqueue(
    () => _write(() async {
      if (!_db.cardStatementsAware) {
        throw UnsupportedError('Card statements require schema 18');
      }
      await _admitCapacity();
      final prior = await _db
          .customSelect(
            'SELECT 1 FROM card_statements WHERE workspace=? AND operation_id=?',
            variables: [
              Variable(workspace.id.value),
              Variable(operation.id.value),
            ],
          )
          .getSingleOrNull();
      if (prior == null && await _count('card_statements') >= maxEvents) {
        throw PreviewCapacity();
      }
      await card_facts.appendCardStatementRevision(
        _db,
        workspace: workspace,
        statementId: statementId,
        cardId: cardId,
        revision: revision,
        cycle: cycle,
        billed: billed,
        operation: operation,
      );
      if (prior == null) {
        await _checkRows('card_statements', 'workspace=? AND operation_id=?', [
          workspace.id.value,
          operation.id.value,
        ]);
      }
    }),
  );

  Future<List<card_facts.ConfirmedCardStatement>> confirmedCardStatements({
    required WorkspaceId workspace,
    required PublicId cardId,
  }) => _enqueue(
    () => card_facts.confirmedCardStatements(_db, workspace, cardId),
  );

  Future<List<card_facts.CardUnallocatedPayment>> unallocatedCardPayments({
    required WorkspaceId workspace,
    required PublicId cardId,
  }) => _enqueue(
    () => card_facts.unallocatedCardPayments(_db, workspace, cardId),
  );

  Future<void> allocateCardPayment({
    required WorkspaceId workspace,
    required PublicId paymentEventId,
    required PublicId statementId,
    required int statementRevision,
    required Money amount,
    required OperationId operation,
  }) => _enqueue(
    () => _write(() async {
      if (!_db.cardStatementsAware) {
        throw UnsupportedError('Card statements require schema 18');
      }
      await _admitCapacity();
      final prior = await _db
          .customSelect(
            'SELECT 1 FROM card_payment_allocations '
            'WHERE workspace=? AND operation_id=?',
            variables: [
              Variable(workspace.id.value),
              Variable(operation.id.value),
            ],
          )
          .getSingleOrNull();
      if (prior == null &&
          await _count('card_payment_allocations') >= SnapshotCodec.maxRows) {
        throw PreviewCapacity();
      }
      await card_facts.allocateCardPayment(
        _db,
        workspace: workspace,
        paymentEventId: paymentEventId,
        statementId: statementId,
        statementRevision: statementRevision,
        amount: amount,
        operation: operation,
      );
      if (prior == null) {
        await _checkRows(
          'card_payment_allocations',
          'workspace=? AND operation_id=?',
          [workspace.id.value, operation.id.value],
        );
      }
    }),
  );

  Future<CardTermsRevision> reviseCreditCard(
    CreditCardTerms terms,
    OperationId operation,
    DateTime recordedAt, {
    bool disabled = false,
  }) => _enqueue(
    () => _write(() async {
      if (!_db.creditCardsAware) {
        throw UnsupportedError('Credit cards require schema 17');
      }
      await _admitCapacity();
      final existing = await _db
          .customSelect(
            'SELECT 1 FROM card_revisions WHERE workspace=? AND operation_id=?',
            variables: [
              Variable.withString(terms.workspace.id.value),
              Variable.withString(operation.id.value),
            ],
          )
          .getSingleOrNull();
      if (existing == null &&
          await _count('card_revisions') >= maxCardChanges) {
        throw PreviewCapacity();
      }
      final result = await appendCardTermsRevision(
        _db,
        terms,
        operation,
        recordedAt,
        disabled: disabled,
      );
      if (existing == null) {
        await _checkRows('card_revisions', 'workspace=? AND operation_id=?', [
          terms.workspace.id.value,
          operation.id.value,
        ]);
      }
      return result;
    }),
  );

  Future<CommitResult> post(
    Posting posting, {
    Iterable<TagSelection> tags = const [],
    MerchantSelection? merchant,
  }) => _post(posting, tags: tags, merchant: merchant);

  /// Commits one settled, same-currency card purchase as a Ledger expense.
  /// The event ID is also the charge identity; no authorization is stored.
  /// The card balance becomes more negative, while report expense rises once.
  Future<CommitResult> postCardPurchase(
    Posting purchase, {
    Iterable<TagSelection> tags = const [],
    MerchantSelection? merchant,
  }) => _post(purchase, tags: tags, merchant: merchant, cardPurchase: true);

  /// Pays an outstanding card liability from a bank account. This account-
  /// level transfer is not assigned to an issuer statement and adds no spend.
  Future<CommitResult> postCardPayment(Posting payment) =>
      _post(payment, cardPayment: true);

  Future<CommitResult> _post(
    Posting posting, {
    Iterable<TagSelection> tags = const [],
    MerchantSelection? merchant,
    bool cardPurchase = false,
    bool cardPayment = false,
  }) {
    final selections = canonicalTags(tags);
    return _enqueue(
      () => _write(() async {
        if (cardPurchase) {
          if (!_db.creditCardsAware) {
            throw UnsupportedError('Credit cards require schema 17');
          }
          if (posting.kind != PostingKind.expense ||
              posting.legs.length != 1 ||
              posting.legs.single.role != LegRole.principal) {
            throw ArgumentError('Card purchase requires one expense leg');
          }
          // A committed operation remains replayable after the card is
          // disabled; FinancialWorkflows still checks its exact input.
          if (!await _hasOperation(posting.operation)) {
            final account = await AccountsAdapter(
              _db,
            ).read(posting.operation.workspace, posting.legs.single.account.id);
            if (account.kind != AccountKind.creditCard) {
              throw const CreditCardException(CreditCardError.cardMismatch);
            }
            final terms = await currentCardTerms(
              _db,
              posting.operation.workspace,
            );
            if (!terms.any(
              (term) =>
                  term.cardId == account.id &&
                  term.currency == account.currency,
            )) {
              throw const FormatException('Card is disabled or unconfigured');
            }
            if (account.currency != posting.reportExpense.currency) {
              throw const CreditCardException(CreditCardError.currencyMismatch);
            }
          }
        }
        if (cardPayment) {
          if (!_db.creditCardsAware) {
            throw UnsupportedError('Credit cards require schema 17');
          }
          if (posting.kind != PostingKind.transfer ||
              posting.legs.length != 2 ||
              posting.legs.any((leg) => leg.role != LegRole.principal) ||
              posting.reportIncome.minorUnits != BigInt.zero ||
              posting.reportExpense.minorUnits != BigInt.zero) {
            throw ArgumentError('Card payment requires a fee-free transfer');
          }
          if (posting.conversion != null ||
              posting.legs.first.amount.currency !=
                  posting.legs.last.amount.currency) {
            throw const CreditCardException(CreditCardError.currencyMismatch);
          }
          // A successful payment must replay even though it has reduced the
          // outstanding liability. The receipt still verifies exact input.
          if (!await _hasOperation(posting.operation)) {
            final accounts = AccountsAdapter(_db);
            final source = await accounts.read(
              posting.operation.workspace,
              posting.legs.first.account.id,
            );
            final target = await accounts.read(
              posting.operation.workspace,
              posting.legs.last.account.id,
            );
            if (source.kind != AccountKind.bank ||
                target.kind != AccountKind.creditCard) {
              throw const CreditCardException(CreditCardError.cardMismatch);
            }
            if (source.currency != target.currency ||
                posting.legs.last.amount.currency != target.currency) {
              throw const CreditCardException(CreditCardError.currencyMismatch);
            }
            final revisions = await cardTermsHistory(
              _db,
              posting.operation.workspace,
            );
            if (!revisions.any(
              (revision) =>
                  revision.terms.cardId == target.id &&
                  revision.terms.currency == target.currency,
            )) {
              throw const FormatException('Card is unconfigured');
            }
            final liability = await LedgerAdapter(_db)
                .balance(posting.legs.last.account);
            if (liability.minorUnits >= BigInt.zero ||
                posting.legs.last.amount.minorUnits > -liability.minorUnits) {
              throw const CreditCardException(CreditCardError.invalidInput);
            }
          }
        }
        if (!cardPurchase && !cardPayment) {
          await _rejectUntrackedCardPosting(_db, posting);
        }
        if (posting.kind != PostingKind.income &&
            posting.kind != PostingKind.expense &&
            !(_db.transfersAware && posting.kind == PostingKind.transfer) &&
            !(_db.refundsAware && posting.kind == PostingKind.refund) &&
            !(_db.reversalsAware && posting.kind == PostingKind.reversal)) {
          throw UnsupportedError('Unsupported session posting');
        }
        if (posting.kind == PostingKind.transfer &&
            (selections.isNotEmpty || merchant != null)) {
          throw UnsupportedError('Transfer metadata is not yet supported');
        }
        await _capacity(posting);
        final result = await FinancialWorkflows(
          _db,
          sourceContext: 'preview-manual-v1',
        ).post(posting, tags: selections, merchant: merchant);
        if (_db.cardStatementsAware && cardPurchase) {
          await card_facts.registerPostedCardCharge(
            _db,
            posting.operation.workspace,
            posting.id,
            posting.legs.single.account.id,
          );
        }
        if (_db.cardStatementsAware && cardPayment) {
          await card_facts.registerCardPayment(
            _db,
            posting.operation.workspace,
            posting.id,
            posting.legs.last.account.id,
          );
        }
        if (!result.replayed) {
          await _checkFinancialRows(posting);
          if (_db.merchantsAware)
            await _checkRows('event_merchants', 'workspace=? AND event_id=?', [
              posting.operation.workspace.toString(),
              posting.id.value,
            ]);
          if (_db.tagsAware)
            await _checkRows('event_tags', 'workspace=? AND event_id=?', [
              posting.operation.workspace.toString(),
              posting.id.value,
            ]);
        }
        return result;
      }),
    );
  }

  Future<CorrectionCommitResult> correct(
    PostingCorrection correction, {
    Iterable<TagSelection> replacementTags = const [],
    MerchantSelection? replacementMerchant,
  }) {
    final selections = canonicalTags(replacementTags);
    return _enqueue(
      () => _write(() async {
        if (!_db.correctionsAware) {
          throw UnsupportedError('Corrections require schema 13.');
        }
        await _rejectUntrackedCardPosting(_db, correction.original);
        await _rejectUntrackedCardPosting(_db, correction.replacement);
        if (correction.replacement.kind == PostingKind.transfer &&
            (selections.isNotEmpty || replacementMerchant != null)) {
          throw UnsupportedError('Transfer metadata is not yet supported');
        }
        final previousReversal = await _hasOperation(
          correction.reversal.operation,
        );
        final previousReplacement = await _hasOperation(
          correction.replacement.operation,
        );
        if (!previousReversal && !previousReplacement) {
          await _admitCapacity();
          if (await _count('events') > maxEvents - 2 ||
              await _count('event_corrections') >= maxEvents ~/ 2) {
            throw PreviewCapacity();
          }
        }
        final result =
            await FinancialWorkflows(
              _db,
              sourceContext: 'preview-manual-v1',
            ).correct(
              correction,
              replacementTags: selections,
              replacementMerchant: replacementMerchant,
            );
        if (!result.replayed) {
          await _checkFinancialRows(correction.reversal);
          await _checkFinancialRows(correction.replacement);
          await _checkRows(
            'event_corrections',
            'workspace=? AND original_id=?',
            [
              correction.original.operation.workspace.toString(),
              correction.original.id.value,
            ],
          );
        }
        return result;
      }),
    );
  }

  Future<CommitResult> tombstone(PostingTombstone command) => _enqueue(
    () => _write(() async {
      if (!_db.tombstonesAware) {
        throw UnsupportedError('Tombstones require schema 14.');
      }
      await _rejectUntrackedCardPosting(_db, command.original);
      if (!await _hasOperation(command.operation)) {
        await _admitCapacity();
        if (await _count('event_tombstones') >= maxEvents) {
          throw PreviewCapacity();
        }
      }
      final result = await FinancialWorkflows(_db).tombstone(command);
      if (!result.replayed) {
        final values = [
          command.operation.workspace.toString(),
          command.original.id.value,
        ];
        await _checkRows(
          'event_tombstones',
          'workspace=? AND event_id=?',
          values,
        );
        await _checkOperationRows(command.operation);
      }
      return result;
    }),
  );

  Future<List<AccountSummary>> accounts(WorkspaceId workspace) =>
      _enqueue(() async {
        final rows = await _db
            .customSelect(
              'SELECT id FROM accounts WHERE workspace=? ORDER BY id',
              variables: [Variable.withString(workspace.toString())],
            )
            .get();
        final adapter = AccountsAdapter(_db);
        final ledger = LedgerAdapter(_db);
        return List.unmodifiable(
          await Future.wait(
            rows.map((row) async {
              final account = await adapter.read(
                workspace,
                PublicId.parse(row.read<String>('id')),
              );
              final balance = await ledger.balance(
                PostingAccount(
                  id: account.id,
                  workspace: workspace,
                  currency: account.currency,
                  expectedVersion: account.version,
                ),
              );
              return AccountSummary(account, balance);
            }),
          ),
        );
      });

  Future<ReversalSourceRecord> reversalSource(
    WorkspaceId workspace,
    PublicId original,
  ) => _enqueue(() => readReversalSource(_db, workspace, original));

  Future<RefundStatus> refundStatus(
    WorkspaceId workspace,
    PublicId originalId,
  ) => _enqueue(() async {
    final r = await readRefundSource(_db, workspace, originalId);
    return RefundStatus(
      r.accountId,
      r.originalAmount,
      r.budget,
      r.tags,
      r.merchant,
    );
  });

  String get _entrySelect =>
      'SELECT e.id,e.business_date,e.kind,l.account_id,l.amount,l.currency,l.scale,'
      'd.account_id AS destination_id,d.amount AS received_amount,d.currency AS received_currency,d.scale AS received_scale,e.expense AS fee,'
      'e.currency AS report_currency,e.scale AS report_scale,'
      "${_db.notesAware ? '(SELECT text FROM event_note_revisions n WHERE n.workspace=e.workspace AND n.event_id=e.id ORDER BY revision DESC LIMIT 1)' : 'NULL'} AS note_text,"
      "${_db.notesAware ? '(SELECT revision FROM event_note_revisions n WHERE n.workspace=e.workspace AND n.event_id=e.id ORDER BY revision DESC LIMIT 1)' : 'NULL'} AS note_revision,"
      '${_db.refundsAware ? 'r.original_id' : 'NULL'} AS refund_of,'
      '${_db.reversalsAware ? 'v.original_id' : 'NULL'} AS reversal_of,'
      '${_db.reversalsAware ? 'v.reason' : 'NULL'} AS reversal_reason,'
      '${_db.reversalsAware ? 'b.event_id' : 'NULL'} AS reversed_by,'
      '${_db.correctionsAware ? 'c.replacement_id' : 'NULL'} AS corrected_by,'
      '${_db.tombstonesAware ? 't.reason' : 'NULL'} AS tombstone_reason '
      'FROM events e JOIN legs l ON l.workspace=e.workspace AND l.event_id=e.id AND l.ordinal=0 '
      'LEFT JOIN legs d ON d.workspace=e.workspace AND d.event_id=e.id AND d.ordinal=1 '
      '${_db.refundsAware ? 'LEFT JOIN event_refunds r ON r.workspace=e.workspace AND r.event_id=e.id ' : ''}'
      '${_db.reversalsAware ? 'LEFT JOIN event_reversals v ON v.workspace=e.workspace AND v.event_id=e.id LEFT JOIN event_reversals b ON b.workspace=e.workspace AND b.original_id=e.id ' : ''}'
      '${_db.correctionsAware ? 'LEFT JOIN event_corrections c ON c.workspace=e.workspace AND c.original_id=e.id ' : ''}'
      '${_db.tombstonesAware ? 'LEFT JOIN event_tombstones t ON t.workspace=e.workspace AND t.event_id=e.id ' : ''}';

  /// Persisted entry in this workspace, independent of pagination or UI state.
  Future<LedgerEntry?> entry(WorkspaceId workspace, PublicId id) =>
      _enqueue(() async {
        final row = await _db
            .customSelect(
              _entrySelect + 'WHERE e.workspace=? AND e.id=?',
              variables: [
                Variable.withString(workspace.toString()),
                Variable.withString(id.value),
              ],
            )
            .getSingleOrNull();
        return row == null ? null : _entryFromRow(row);
      });

  /// Keyset pagination by business date and public ID; no OFFSET drift.
  Future<List<LedgerEntry>> entries(
    WorkspaceId workspace, {
    LedgerEntry? before,
    int limit = 30,
  }) => _enqueue(() async {
    if (limit < 1 || limit > 100) throw ArgumentError.value(limit, 'limit');
    final rows = await _db
        .customSelect(
          _entrySelect +
              'WHERE e.workspace=? ${_db.tombstonesAware ? 'AND t.event_id IS NULL ' : ''}${before == null ? '' : 'AND (e.business_date < ? OR (e.business_date = ? AND e.id < ?))'} '
                  'ORDER BY e.business_date DESC,e.id DESC LIMIT ?',
          variables: [
            Variable.withString(workspace.toString()),
            if (before != null) ...[
              Variable.withString(before.date.toString()),
              Variable.withString(before.date.toString()),
              Variable.withString(before.id.value),
            ],
            Variable.withInt(limit),
          ],
        )
        .get();
    return List.unmodifiable(rows.map(_entryFromRow));
  });

  /// Reads the authoritative Ledger with AND predicates and a stable keyset.
  /// No index or projection is persisted, so an immediately repeated search
  /// observes completed writes and restores from the same session.
  Future<List<LedgerEntry>> searchEntries(
    WorkspaceId workspace,
    LedgerSearchQuery query, {
    LedgerEntry? before,
    int limit = 30,
  }) => _enqueue(() async {
    if (limit < 1 || limit > 100) throw ArgumentError.value(limit, 'limit');
    if (query.categoryId != null && !_db.categoryAware ||
        query.tagId != null && !_db.tagsAware ||
        query.merchantId != null && !_db.merchantsAware ||
        query.noteContains != null && !_db.notesAware) {
      throw UnsupportedError('Search condition is unavailable in this schema.');
    }
    final filter = StringBuffer('WHERE e.workspace=? ');
    final values = <Variable<Object>>[
      Variable.withString(workspace.toString()),
    ];
    if (_db.tombstonesAware) filter.write('AND t.event_id IS NULL ');
    if (query.from != null) {
      filter.write('AND e.business_date>=? ');
      values.add(Variable.withString(query.from.toString()));
    }
    if (query.through != null) {
      filter.write('AND e.business_date<=? ');
      values.add(Variable.withString(query.through.toString()));
    }
    if (query.accountId != null) {
      filter.write(
        'AND EXISTS (SELECT 1 FROM legs x WHERE x.workspace=e.workspace '
        'AND x.event_id=e.id AND x.account_id=?) ',
      );
      values.add(Variable.withString(query.accountId!.value));
    }
    if (query.categoryId != null) {
      filter.write(
        'AND EXISTS (SELECT 1 FROM allocations x WHERE x.workspace=e.workspace '
        'AND x.event_id=e.id AND x.category_id=?) ',
      );
      values.add(Variable.withString(query.categoryId!.value));
    }
    if (query.tagId != null) {
      filter.write(
        'AND EXISTS (SELECT 1 FROM event_tags x WHERE x.workspace=e.workspace '
        'AND x.event_id=e.id AND x.tag_id=?) ',
      );
      values.add(Variable.withString(query.tagId!.value));
    }
    if (query.merchantId != null) {
      filter.write(
        'AND EXISTS (SELECT 1 FROM event_merchants x WHERE x.workspace=e.workspace '
        'AND x.event_id=e.id AND x.merchant_id=?) ',
      );
      values.add(Variable.withString(query.merchantId!.value));
    }
    if (query.currency != null) {
      filter.write('AND l.currency=? AND l.scale=? ');
      values.add(Variable.withString(query.currency!.code));
      values.add(Variable.withInt(query.currency!.scale));
    }
    if (query.kind != null) {
      filter.write('AND e.kind=? ');
      values.add(Variable.withString(query.kind!.name));
    }
    if (query.minAbsAmount != null) {
      // Avoid abs(-2^63), which overflows SQLite's signed integer range.
      final lower = query.minAbsAmount!.minorUnits.toInt();
      filter.write('AND (l.amount>=? OR l.amount<=?) ');
      values.add(Variable.withInt(lower));
      values.add(Variable.withInt(-lower));
    }
    if (query.maxAbsAmount != null) {
      final upper = query.maxAbsAmount!.minorUnits.toInt();
      filter.write('AND l.amount BETWEEN ? AND ? ');
      values.add(Variable.withInt(-upper));
      values.add(Variable.withInt(upper));
    }
    if (query.noteContains != null) {
      filter.write(
        'AND instr(lower(COALESCE((SELECT n.text FROM event_note_revisions n '
        'WHERE n.workspace=e.workspace AND n.event_id=e.id '
        "ORDER BY n.revision DESC LIMIT 1),'')),lower(?))>0 ",
      );
      values.add(Variable.withString(query.noteContains!));
    }
    if (before != null) {
      filter.write(
        'AND (e.business_date < ? OR (e.business_date = ? AND e.id < ?)) ',
      );
      values.addAll([
        Variable.withString(before.date.toString()),
        Variable.withString(before.date.toString()),
        Variable.withString(before.id.value),
      ]);
    }
    values.add(Variable.withInt(limit));
    final rows = await _db
        .customSelect(
          '$_entrySelect$filter ORDER BY e.business_date DESC,e.id DESC LIMIT ?',
          variables: values,
        )
        .get();
    return List.unmodifiable(rows.map(_entryFromRow));
  });

  /// Rebuilds this month's financial report from committed event report facts.
  /// The Ledger's signed income/expense fields already encode refunds, fees
  /// and reversals; tombstoned events leave the effective view. Each currency
  /// is kept separate and no exchange rate is inferred.
  Future<MonthlyReport> monthlyReport(
    WorkspaceId workspace,
    ReportMonth month,
  ) => _enqueue(() async {
    final rows = await _db
        .customSelect(
          'SELECT e.id,e.business_date,e.kind,e.income,e.expense,e.currency,e.scale,p.account_id AS primary_account_id, '
          '${_db.categoryReferences ? 'a.category_id,a.amount AS allocated_amount,' : 'NULL AS category_id,NULL AS allocated_amount,'}'
          '${_db.tagsAware ? '(SELECT group_concat(x.tag_id) FROM event_tags x WHERE x.workspace=e.workspace AND x.event_id=e.id) AS tag_ids,' : 'NULL AS tag_ids,'}'
          '${_db.merchantsAware ? 'm.merchant_id ' : 'NULL AS merchant_id '}'
          'FROM events e '
          'LEFT JOIN legs p ON p.workspace=e.workspace AND p.event_id=e.id AND p.ordinal=0 '
          '${_db.categoryReferences ? 'LEFT JOIN allocations a ON a.workspace=e.workspace AND a.event_id=e.id ' : ''}'
          '${_db.merchantsAware ? 'LEFT JOIN event_merchants m ON m.workspace=e.workspace AND m.event_id=e.id ' : ''}'
          '${_db.tombstonesAware ? 'LEFT JOIN event_tombstones t ON t.workspace=e.workspace AND t.event_id=e.id ' : ''}'
          'WHERE e.workspace=? AND e.business_date>=? AND e.business_date<=? '
          '${_db.tombstonesAware ? 'AND t.event_id IS NULL ' : ''}'
          'ORDER BY e.business_date DESC,e.id DESC${_db.categoryReferences ? ',a.category_id' : ''}',
          variables: [
            Variable.withString(workspace.toString()),
            Variable.withString(month.first.toString()),
            Variable.withString(month.last.toString()),
          ],
        )
        .get();
    final grouped = <String, List<QueryRow>>{};
    for (final row in rows) {
      if (row.read<String?>('primary_account_id') == null) {
        throw const FormatException('Report event lacks a primary account.');
      }
      grouped.putIfAbsent(row.read<String>('id'), () => []).add(row);
    }
    return MonthlyReport.build(month, [
      for (final eventRows in grouped.values)
        MonthlyFact(
          id: PublicId.parse(eventRows.first.read<String>('id')),
          date: BusinessDate.parse(
            eventRows.first.read<String>('business_date'),
          ),
          kind: PostingKind.values.byName(eventRows.first.read<String>('kind')),
          income: Money(
            Currency(
              eventRows.first.read<String>('currency'),
              eventRows.first.read<int>('scale'),
            ),
            BigInt.from(eventRows.first.read<int>('income')),
          ),
          expense: Money(
            Currency(
              eventRows.first.read<String>('currency'),
              eventRows.first.read<int>('scale'),
            ),
            BigInt.from(eventRows.first.read<int>('expense')),
          ),
          accountId: PublicId.parse(
            eventRows.first.read<String>('primary_account_id'),
          ),
          merchantId: switch (eventRows.first.read<String?>('merchant_id')) {
            final id? => PublicId.parse(id),
            null => null,
          },
          tagIds: switch (eventRows.first.read<String?>('tag_ids')) {
            final ids? => ids.split(',').map(PublicId.parse).toSet(),
            null => const <PublicId>{},
          },
          allocations: [
            for (final row in eventRows)
              if (row.read<String?>('category_id') case final categoryId?)
                CategoryAllocation(
                  PublicId.parse(categoryId),
                  Money(
                    Currency(
                      row.read<String>('currency'),
                      row.read<int>('scale'),
                    ),
                    BigInt.from(row.read<int>('allocated_amount')),
                  ),
                ),
          ],
        ),
    ]);
  });

  /// Historical deleted entries remain inspectable, but never enter the
  /// effective list or balance. Uses the same stable keyset as active entries.
  Future<List<LedgerEntry>> deletedEntries(
    WorkspaceId workspace, {
    LedgerEntry? before,
    int limit = 30,
  }) => _enqueue(() async {
    if (limit < 1 || limit > 100) throw ArgumentError.value(limit, 'limit');
    if (!_db.tombstonesAware) return const <LedgerEntry>[];
    final rows = await _db
        .customSelect(
          _entrySelect +
              'WHERE e.workspace=? AND t.event_id IS NOT NULL '
                  '${before == null ? '' : 'AND (e.business_date < ? OR (e.business_date = ? AND e.id < ?))'} '
                  'ORDER BY e.business_date DESC,e.id DESC LIMIT ?',
          variables: [
            Variable.withString(workspace.toString()),
            if (before != null) ...[
              Variable.withString(before.date.toString()),
              Variable.withString(before.date.toString()),
              Variable.withString(before.id.value),
            ],
            Variable.withInt(limit),
          ],
        )
        .get();
    return List.unmodifiable(rows.map(_entryFromRow));
  });

  Future<List<int>> snapshot() => _enqueue(
    () => SnapshotCodec(
      generationAware: true,
      categoryAware: _db.categoryAware,
      categoryReferences: _db.categoryReferences,
      tagsAware: _db.tagsAware,
      merchantsAware: _db.merchantsAware,
      transfersAware: _db.transfersAware,
      fxTransfersAware: _db.fxTransfersAware,
      refundsAware: _db.refundsAware,
      reversalsAware: _db.reversalsAware,
      notesAware: _db.notesAware,
      correctionsAware: _db.correctionsAware,
      tombstonesAware: _db.tombstonesAware,
      budgetsAware: _db.budgetsAware,
      recurringAware: _db.recurringAware,
      creditCardsAware: _db.creditCardsAware,
      cardStatementsAware: _db.cardStatementsAware,
    ).capture(_db),
  );

  Future<List<WorkspaceId>> workspaces() => _enqueue(() async {
    final rows = await _db
        .customSelect(
          'SELECT DISTINCT workspace FROM accounts '
          '${_db.categoryAware ? 'UNION SELECT workspace FROM categories ' : ''}'
          '${_db.tagsAware ? 'UNION SELECT workspace FROM tags ' : ''}'
          '${_db.merchantsAware ? 'UNION SELECT workspace FROM merchants ' : ''}'
          'ORDER BY workspace',
        )
        .get();
    return List.unmodifiable(
      rows.map((r) => WorkspaceId.parse(r.read<String>('workspace'))),
    );
  });
}

/// Prevent older generic entry points from posting card activity without a
/// card workflow. A card purchase deliberately bypasses this guard only after
/// its account and active settings have been checked in the same transaction.
Future<void> _rejectUntrackedCardPosting(
  ProbeDatabase db,
  Posting posting,
) async {
  if (!db.creditCardsAware) return;
  final accounts = AccountsAdapter(db);
  for (final leg in posting.legs) {
    final account = await accounts.read(
      posting.operation.workspace,
      leg.account.id,
    );
    if (account.kind == AccountKind.creditCard) {
      throw UnsupportedError('Use a credit-card posting workflow');
    }
  }
}

LedgerEntry _entryFromRow(QueryRow r) => LedgerEntry(
  PublicId.parse(r.read<String>('id')),
  BusinessDate.parse(r.read<String>('business_date')),
  PostingKind.values.byName(r.read<String>('kind')),
  PublicId.parse(r.read<String>('account_id')),
  Money(
    Currency(r.read<String>('currency'), r.read<int>('scale')),
    BigInt.from(r.read<int>('amount')),
  ),
  reversalOf: r.readNullable<String>('reversal_of') == null
      ? null
      : PublicId.parse(r.read<String>('reversal_of')),
  reversedBy: r.readNullable<String>('reversed_by') == null
      ? null
      : PublicId.parse(r.read<String>('reversed_by')),
  correctedBy: r.readNullable<String>('corrected_by') == null
      ? null
      : PublicId.parse(r.read<String>('corrected_by')),
  reversalReason: r.readNullable<String>('reversal_reason'),
  tombstoneReason: r.readNullable<String>('tombstone_reason'),
  note: EntryNote(
    r.readNullable<int>('note_revision') ?? 0,
    r.readNullable<String>('note_text') ?? '',
  ),
  refundOf: r.readNullable<String>('refund_of') == null
      ? null
      : PublicId.parse(r.read<String>('refund_of')),
  refunded: r.read<String>('kind') == 'refund'
      ? Money(
          Currency(
            r.read<String>('report_currency'),
            r.read<int>('report_scale'),
          ),
          -BigInt.from(r.read<int>('fee')),
        )
      : null,
  destinationId: r.readNullable<String>('destination_id') == null
      ? null
      : PublicId.parse(r.read<String>('destination_id')),
  received: r.readNullable<String>('destination_id') == null
      ? null
      : Money(
          Currency(
            r.read<String>('received_currency'),
            r.read<int>('received_scale'),
          ),
          BigInt.from(r.read<int>('received_amount')),
        ),
  fee: r.readNullable<String>('destination_id') != null
      ? Money(
          Currency(r.read<String>('currency'), r.read<int>('scale')),
          BigInt.from(r.read<int>('fee')),
        )
      : null,
);

final class RefundStatus {
  const RefundStatus(
    this.originalAccountId,
    this.originalAmount,
    this.budget,
    this.tags,
    this.merchant,
  );
  final PublicId originalAccountId;
  final Money originalAmount;
  final RefundBudget budget;
  final List<TagSelection> tags;
  final MerchantSelection? merchant;
}
