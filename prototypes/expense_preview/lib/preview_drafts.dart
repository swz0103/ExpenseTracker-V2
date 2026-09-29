part of 'preview_engine.dart';

extension PreviewDrafts on PreviewEngine {
  Future<T> _draftExclusive<T>(Future<T> Function(int) work) =>
      _exclusive((epoch) async {
        _draftActive = true;
        try {
          return await work(epoch);
        } finally {
          _draftActive = false;
        }
      });

  LocalDraftStore get _drafts {
    _require();
    return _draftStore ?? (throw PreviewInvalid());
  }

  Future<void> _commitPreparedPosting(EntryDraft draft, int epoch) async {
    final command = draft.submission!;
    final accountId = draft.fields.accountId;
    if (draft.fields.transfer &&
        (accountId == null ||
            command.posting.kind != PostingKind.transfer ||
            command.posting.legs.length < 2 ||
            command.posting.legs.first.account.id != accountId ||
            command.posting.legs.first.role != LegRole.principal ||
            command.posting.legs[1].role != LegRole.principal ||
            command.posting.legs[1].account.id != draft.fields.destinationId)) {
      throw PreviewInvalid();
    }
    final isCard =
        accountId != null &&
        (await _session!.accounts(workspace)).any(
          (row) =>
              row.account.id == accountId &&
              row.account.kind == AccountKind.creditCard,
        );
    final isCardPayment =
        draft.fields.transfer &&
        draft.fields.destinationId != null &&
        (await _session!.accounts(workspace)).any(
          (row) =>
              row.account.id == draft.fields.destinationId &&
              row.account.kind == AccountKind.creditCard,
        );
    _check(epoch);
    if (isCard && command.posting.kind == PostingKind.refund) {
      if (!capabilities.cardAuthorizations) throw PreviewInvalid();
      await _session!.postCardRefund(
        command.posting,
        tags: command.tags,
        merchant: command.merchant,
      );
    } else if (isCard) {
      await _session!.postCardPurchase(
        command.posting,
        tags: command.tags,
        merchant: command.merchant,
      );
    } else if (isCardPayment) {
      await _session!.postCardPayment(command.posting);
    } else {
      await _session!.post(
        command.posting,
        tags: command.tags,
        merchant: command.merchant,
      );
    }
  }

  Future<EntryDraft?> entryDraft() => _draftExclusive((epoch) async {
    final store = _drafts;
    final session = _session!;
    final draft = await store.read();
    _check(epoch);
    if (draft?.tombstoneSubmission != null &&
        (await session.entry(workspace, draft!.id))?.tombstoneReason != null) {
      await session.tombstone(draft.tombstoneSubmission!.command);
      await store.write(null);
      _check(epoch);
      return null;
    }
    if (draft?.noteSubmission != null &&
        await session.noteOperationExists(draft!.operation)) {
      await session.reviseNote(draft.operation, draft.noteSubmission!);
      await store.write(null);
      _check(epoch);
      return null;
    }
    if (draft?.correctionSubmission != null &&
        await session.entry(workspace, draft!.id) != null) {
      final frozen = draft.correctionSubmission!;
      await session.correct(
        frozen.pair,
        replacementTags: frozen.tags,
        replacementMerchant: frozen.merchant,
      );
      await store.write(null);
      _check(epoch);
      return null;
    }
    if (draft?.submission != null &&
        await session.entry(workspace, draft!.id) != null) {
      // Receipt equality proves this event is exactly our frozen command.
      await _commitPreparedPosting(draft, epoch);
      await store.write(null);
      _check(epoch);
      return null;
    }
    _check(epoch);
    return draft;
  });

  Future<EntryDraft> saveEntryDraft(EntryFields fields) => _draftExclusive((
    epoch,
  ) async {
    final store = _drafts;
    if ((fields.tombstoneOf != null && !capabilities.tombstones) ||
        (fields.correctionOf != null && !capabilities.corrections) ||
        (fields.noteOf != null && !capabilities.notes) ||
        (fields.reversalOf != null && !capabilities.reversals) ||
        (fields.refundOf != null && !capabilities.refunds) ||
        (fields.transfer && !capabilities.transfers) ||
        (fields.received != null && !capabilities.crossCurrencyTransfers) ||
        (fields.split && !capabilities.split)) {
      throw PreviewInvalid();
    }
    final prior = await store.read();
    _check(epoch);
    if (prior?.isPrepared == true) throw DraftNeedsResolution();
    final draft =
        prior?.edit(fields) ??
        EntryDraft(
          id: fields.tombstoneOf ?? PublicId.generate(),
          operation: OperationKey(workspace, OperationId(PublicId.generate())),
          fields: fields,
        );
    await store.write(draft);
    _check(epoch);
    return draft;
  });

  Future<void> discardEntryDraft() => _draftExclusive((epoch) async {
    final store = _drafts;
    await store.discard();
    _check(epoch);
  });

  Future<void> _requireNoDraft() async {
    if (await _drafts.read() != null) throw DraftNeedsResolution();
  }

  Future<void> submitEntryDraft() => _draftExclusive((epoch) async {
    final store = _drafts;
    final session = _session!;
    var draft = await store.read();
    _check(epoch);
    if (draft == null) throw PreviewInvalid();
    if (draft.fields.tombstoneOf != null) {
      if (!capabilities.tombstones) throw PreviewInvalid();
      if (!draft.isPrepared) {
        final source = await session.reversalSource(
          workspace,
          draft.fields.tombstoneOf!,
        );
        _check(epoch);
        draft = draft.prepareTombstone(
          TombstoneSubmission(
            PostingTombstone(
              original: source.posting,
              operation: draft.operation,
              reason: draft.fields.tombstoneReason.trim(),
            ),
          ),
        );
        await store.write(draft);
        draftCheckpoint?.call('draft-prepared');
        _check(epoch);
      }
      await session.tombstone(draft.tombstoneSubmission!.command);
      draftCheckpoint?.call('draft-committed');
      await store.write(null);
      _check(epoch);
      return;
    }
    if (draft.fields.noteOf != null) {
      if (!capabilities.notes) throw PreviewInvalid();
      if (!draft.isPrepared) {
        final f = draft.fields;
        draft = draft.prepareNote(
          NoteChange(f.noteOf!, f.noteRevision, f.noteText),
        );
        await store.write(draft);
        draftCheckpoint?.call('draft-prepared');
        _check(epoch);
      }
      await session.reviseNote(draft.operation, draft.noteSubmission!);
      draftCheckpoint?.call('draft-committed');
      await store.write(null);
      _check(epoch);
      return;
    }
    if (draft.submission == null && draft.correctionSubmission == null) {
      final fields = draft.fields;
      late EntrySubmission command;
      if (fields.reversalOf != null) {
        final source = await session.reversalSource(
          workspace,
          fields.reversalOf!,
        );
        command = EntrySubmission(
          Posting.reversal(
            id: draft.id,
            operation: draft.operation,
            date: BusinessDate.parse(fields.date),
            original: source.posting,
            reason: fields.reversalReason.trim(),
          ),
          tags: source.tags,
          merchant: source.merchant,
        );
      } else {
        final accounts = await session.accounts(workspace);
        final account = accounts
            .where((a) => a.account.id == fields.accountId)
            .firstOrNull
            ?.account;
        final inactiveCardRefund =
            fields.refundOf != null &&
            capabilities.cardAuthorizations &&
            account?.kind == AccountKind.creditCard;
        if (account == null ||
            (account.state != AccountState.active && !inactiveCardRefund)) {
          if (fields.transfer) throw PreviewTransferAccountInvalid();
          throw PreviewInvalid();
        }
        if (fields.refundOf != null) {
          command = await _refundCommand(draft, account, session);
        } else {
          final amount = Money.parse(account.currency, fields.amount);
          final allocations = <Allocation>[];
          if (fields.categoryId != null) {
            final category = (await session.categories(workspace))
                .get(fields.categoryId!);
            if (category.archived ||
                category.replacementId != null ||
                category.kind !=
                    (fields.income
                        ? CategoryKind.income
                        : CategoryKind.expense)) {
              throw PreviewInvalid();
            }
            allocations.add(
              Allocation(
                category.id,
                amount,
                expectedCategoryVersion: category.version,
              ),
            );
          }
          if (fields.split) {
            if (!capabilities.split || fields.splits.length < 2) {
              throw PreviewSplitInvalid();
            }
            final catalog = await session.categories(workspace);
            final selected = <PublicId>{};
            for (final row in fields.splits) {
              final id = row.categoryId;
              if (id == null || !selected.add(id)) throw PreviewSplitInvalid();
              final category = catalog.get(id);
              if (category.archived ||
                  category.replacementId != null ||
                  category.kind !=
                      (fields.income
                          ? CategoryKind.income
                          : CategoryKind.expense)) {
                throw PreviewSplitInvalid();
              }
              allocations.add(
                Allocation(
                  id,
                  Money.parse(account.currency, row.amount),
                  expectedCategoryVersion: category.version,
                ),
              );
            }
          }
          final tags = <TagSelection>[];
          if (fields.tags.isNotEmpty) {
            if (!capabilities.tags) throw PreviewInvalid();
            final catalog = await session.tags(workspace);
            for (final id in fields.tags) {
              final tag = catalog.get(id);
              if (tag.archived || tag.replacementId != null) {
                throw PreviewInvalid();
              }
              tags.add(TagSelection(id, tag.version));
            }
          }
          MerchantSelection? merchant;
          if (fields.merchantId != null) {
            if (!capabilities.merchants) throw PreviewInvalid();
            final item = (await session.merchants(workspace))
                .get(fields.merchantId!);
            if (item.archived || item.replacementId != null) {
              throw PreviewInvalid();
            }
            merchant = MerchantSelection(item.id, item.version);
          }
          final factory = fields.income ? Posting.income : Posting.expense;
          EntrySubmission transfer() {
            if (!capabilities.transfers) throw PreviewInvalid();
            final destination = accounts
                .where((a) => a.account.id == fields.destinationId)
                .firstOrNull
                ?.account;
            if (destination == null ||
                destination.state != AccountState.active) {
              throw PreviewTransferAccountInvalid();
            }
            PostingAccount ref(Account a) => PostingAccount(
              id: a.id,
              workspace: workspace,
              currency: a.currency,
              expectedVersion: a.version,
            );
            final foreign = account.currency != destination.currency;
            if ((foreign &&
                    (!capabilities.crossCurrencyTransfers ||
                        fields.received == null)) ||
                (!foreign && fields.received != null)) {
              throw PreviewInvalid();
            }
            return EntrySubmission(
              Posting.transfer(
                id: draft!.id,
                operation: draft.operation,
                date: BusinessDate.parse(fields.date),
                source: ref(account),
                destination: ref(destination),
                principal: amount,
                received: fields.received == null
                    ? null
                    : Money.parse(destination.currency, fields.received!),
                fee: Money.parse(account.currency, fields.fee),
              ),
            );
          }

          command = fields.transfer
              ? transfer()
              : EntrySubmission(
                  factory(
                    id: draft.id,
                    operation: draft.operation,
                    date: BusinessDate.parse(fields.date),
                    account: PostingAccount(
                      id: account.id,
                      workspace: workspace,
                      currency: account.currency,
                      expectedVersion: account.version,
                    ),
                    amount: amount,
                    allocations: allocations,
                  ),
                  tags: tags,
                  merchant: merchant,
                );
        }
      }
      _check(epoch);
      if (fields.correctionOf != null) {
        if (!capabilities.corrections) throw PreviewInvalid();
        final source = await session.reversalSource(
          workspace,
          fields.correctionOf!,
        );
        draft = draft.prepareCorrection(
          CorrectionSubmission(
            PostingCorrection(
              original: source.posting,
              replacement: command.posting,
              reversalId: PublicId.generate(),
              reversalOperation: OperationKey(
                workspace,
                OperationId(PublicId.generate()),
              ),
              reason: fields.correctionReason.trim(),
            ),
            tags: command.tags,
            merchant: command.merchant,
          ),
        );
      } else {
        draft = draft.prepare(command);
      }
      await store.write(draft);
      draftCheckpoint?.call('draft-prepared');
      _check(epoch);
    }
    final correction = draft.correctionSubmission;
    if (correction != null) {
      await session.correct(
        correction.pair,
        replacementTags: correction.tags,
        replacementMerchant: correction.merchant,
      );
    } else {
      await _commitPreparedPosting(draft, epoch);
    }
    draftCheckpoint?.call('draft-committed');
    await store.write(null);
    _check(epoch);
  });

  Future<EntryNote> entryNote(PublicId id) => _exclusive((epoch) async {
    _require();
    final note = await _session!.entryNote(workspace, id);
    _check(epoch);
    return note;
  });

  Future<EntryDraft> refreshNoteDraft() => _draftExclusive((epoch) async {
    final store = _drafts;
    final draft = await store.read();
    _check(epoch);
    if (draft == null ||
        draft.fields.noteOf == null ||
        await _session!.noteOperationExists(draft.operation)) {
      throw DraftNeedsResolution();
    }
    final latest = await _session!.entryNote(workspace, draft.fields.noteOf!);
    _check(epoch);
    final next = EntryDraft(
      id: draft.id,
      operation: draft.operation,
      fields: EntryFields(
        income: false,
        amount: '',
        date: '',
        noteOf: draft.fields.noteOf,
        noteRevision: latest.revision,
        noteText: draft.fields.noteText,
      ),
    );
    await store.write(next);
    _check(epoch);
    return next;
  });

  Future<EntrySubmission> reversalSource(PublicId original) =>
      _exclusive((epoch) async {
        _require();
        final source = await _session!.reversalSource(workspace, original);
        _check(epoch);
        return EntrySubmission(
          source.posting,
          tags: source.tags,
          merchant: source.merchant,
        );
      });

  Future<RefundStatus> refundStatus(PublicId original) =>
      _exclusive((epoch) async {
        _require();
        final status = await _session!.refundStatus(workspace, original);
        _check(epoch);
        return status;
      });

  Future<EntrySubmission> _refundCommand(
    EntryDraft draft,
    Account account,
    LedgerSession session,
  ) async {
    if (!capabilities.refunds) throw PreviewInvalid();
    final fields = draft.fields;
    final status = await session.refundStatus(workspace, fields.refundOf!);
    final currency = status.originalAmount.currency;
    final originalAccount = (await session.accounts(workspace))
        .where((row) => row.account.id == status.originalAccountId)
        .firstOrNull
        ?.account;
    if (originalAccount == null) throw PreviewInvalid();
    final cardRefund = originalAccount.kind == AccountKind.creditCard;
    if (cardRefund
        ? !capabilities.cardAuthorizations ||
              account.id != originalAccount.id ||
              account.currency != currency ||
              fields.received != null
        : account.kind == AccountKind.creditCard) {
      throw PreviewInvalid();
    }
    final amount = Money.parse(currency, fields.amount);
    final available = {
      for (final a in status.budget.allocations) a.categoryId: a,
    };
    final selected = <PublicId>{};
    final allocations = <Allocation>[];
    for (final row in fields.splits) {
      final id = row.categoryId;
      if (id == null || !selected.add(id)) throw PreviewInvalid();
      final value = Money.parse(currency, row.amount);
      // Zero is an explicit unselected category, never a Ledger allocation.
      if (value.minorUnits == BigInt.zero) continue;
      final prior = available[id];
      if (prior == null || value.minorUnits < BigInt.zero) {
        throw PreviewInvalid();
      }
      allocations.add(
        Allocation(
          id,
          value,
          expectedCategoryVersion: prior.expectedCategoryVersion,
        ),
      );
    }
    status.budget.consume(
      amount: amount,
      date: BusinessDate.parse(fields.date),
      allocations: allocations,
    );
    final foreign = account.currency != currency;
    if (foreign != (fields.received != null)) throw PreviewInvalid();
    return EntrySubmission(
      Posting.refund(
        id: draft.id,
        operation: draft.operation,
        date: BusinessDate.parse(fields.date),
        account: PostingAccount(
          id: account.id,
          workspace: workspace,
          currency: account.currency,
          expectedVersion: account.version,
        ),
        originalId: fields.refundOf!,
        amount: amount,
        received: foreign
            ? Money.parse(account.currency, fields.received!)
            : null,
        allocations: allocations,
      ),
      tags: status.tags,
      merchant: status.merchant,
    );
  }

  /// Return to editing only after proving no event was committed.
  Future<void> reopenEntryDraft() => _draftExclusive((epoch) async {
    final store = _drafts;
    final session = _session!;
    final draft = await store.read();
    _check(epoch);
    if (draft == null) throw PreviewInvalid();
    if (draft.fields.noteOf != null
        ? await session.noteOperationExists(draft.operation)
        : await session.entry(workspace, draft.id) != null ||
              (draft.correctionSubmission != null &&
                  await session.entry(
                        workspace,
                        draft.correctionSubmission!.pair.reversal.id,
                      ) !=
                      null)) {
      throw DraftNeedsResolution();
    }
    _check(epoch);
    await store.write(
      EntryDraft(
        id: draft.id,
        operation: draft.operation,
        fields: draft.fields,
      ),
    );
    _check(epoch);
  });
}
