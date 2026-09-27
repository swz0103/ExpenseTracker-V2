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
      final account = (await session.accounts(workspace))
          .where((a) => a.account.id == fields.accountId)
          .firstOrNull
          ?.account;
      if (account == null || account.state != AccountState.active) {
        throw PreviewInvalid();
      }
      final amount = Money.parse(account.currency, fields.amount);
      final allocations = <Allocation>[];
      if (fields.categoryId != null) {
        final category = (await session.categories(workspace))
            .get(fields.categoryId!);
        if (category.archived ||
            category.replacementId != null ||
            category.kind !=
                (fields.income ? CategoryKind.income : CategoryKind.expense)) {
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
      final tags = <TagSelection>[];
      if (fields.tags.isNotEmpty) {
        if (schemaVersion < 6) throw PreviewInvalid();
        final catalog = await session.tags(workspace);
        for (final id in fields.tags) {
          final tag = catalog.get(id);
          if (tag.archived || tag.replacementId != null) throw PreviewInvalid();
          tags.add(TagSelection(id, tag.version));
        }
      }
      MerchantSelection? merchant;
      if (fields.merchantId != null) {
        if (schemaVersion < 7) throw PreviewInvalid();
        final item = (await session.merchants(workspace))
            .get(fields.merchantId!);
        if (item.archived || item.replacementId != null) throw PreviewInvalid();
        merchant = MerchantSelection(item.id, item.version);
      }
      final factory = fields.income ? Posting.income : Posting.expense;
      final command = EntrySubmission(
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
