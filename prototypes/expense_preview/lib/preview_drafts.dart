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

  Future<EntryDraft?> entryDraft() => _draftExclusive((epoch) async {
    final store = _drafts;
    final session = _session!;
    final draft = await store.read();
    _check(epoch);
    if (draft?.submission != null &&
        await session.entry(workspace, draft!.id) != null) {
      // Receipt equality proves this event is exactly our frozen command.
      final command = draft.submission!;
      await session.post(
        command.posting,
        tags: command.tags,
        merchant: command.merchant,
      );
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
    if ((fields.reversalOf != null && schemaVersion < 11) ||
        (fields.refundOf != null && schemaVersion < 10) ||
        (fields.transfer && schemaVersion < 8) ||
        (fields.received != null && schemaVersion < 9) ||
        (fields.split && schemaVersion < 5)) {
      throw PreviewInvalid();
    }
    final prior = await store.read();
    _check(epoch);
    if (prior?.submission != null) throw DraftNeedsResolution();
    final draft =
        prior?.edit(fields) ??
        EntryDraft(
          id: PublicId.generate(),
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
    if (draft.submission == null) {
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
        if (account == null || account.state != AccountState.active) {
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
            if (schemaVersion < 5 || fields.splits.length < 2) {
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
            if (schemaVersion < 6) throw PreviewInvalid();
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
            if (schemaVersion < 7) throw PreviewInvalid();
            final item = (await session.merchants(workspace))
                .get(fields.merchantId!);
            if (item.archived || item.replacementId != null) {
              throw PreviewInvalid();
            }
            merchant = MerchantSelection(item.id, item.version);
          }
          final factory = fields.income ? Posting.income : Posting.expense;
          EntrySubmission transfer() {
            if (schemaVersion < 8) throw PreviewInvalid();
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
            if ((foreign && (schemaVersion < 9 || fields.received == null)) ||
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
      draft = draft.prepare(command);
      await store.write(draft);
      draftCheckpoint?.call('draft-prepared');
      _check(epoch);
    }
    final command = draft.submission!;
    await session.post(
      command.posting,
      tags: command.tags,
      merchant: command.merchant,
    );
    draftCheckpoint?.call('draft-committed');
    await store.write(null);
    _check(epoch);
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
    if (schemaVersion < 10) throw PreviewInvalid();
    final fields = draft.fields;
    final status = await session.refundStatus(workspace, fields.refundOf!);
    final currency = status.originalAmount.currency;
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
    if (await session.entry(workspace, draft.id) != null) {
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
