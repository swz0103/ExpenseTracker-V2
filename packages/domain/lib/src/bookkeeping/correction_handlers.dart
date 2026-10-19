part of 'bookkeeping.dart';

/// Reversals, corrections, deletions and notes.
extension _Corrections<T extends BookkeepingTransaction> on Bookkeeping<T> {
  Future<PublicId> _reverse(T t, ReversePosting command) async {
    await _requireNewPosting(t, command.postingId);
    final original = await _reversible(t, command);
    final reversal = Posting.reversal(
      id: command.postingId,
      operation: command.operation,
      date: command.date,
      original: original,
      reason: command.reason,
    );
    await _savePosting(t, reversal, await t.postingMetadata(original.id));
    return reversal.id;
  }

  Future<PublicId> _delete(T t, DeletePosting command) async {
    await _requireNewPosting(t, command.postingId);
    final original = await _reversible(t, command);
    final reversal = Posting.reversal(
      id: command.postingId,
      operation: command.operation,
      date: original.date,
      original: original,
      reason: command.reason.isEmpty ? 'deleted' : command.reason,
    );
    await _savePosting(t, reversal, await t.postingMetadata(original.id));
    return reversal.id;
  }

  Future<PublicId> _correct(T t, CorrectCashFlow command) async {
    await _requireNewPosting(t, command.postingId);
    await _requireNewPosting(t, command.reversalId);
    final workspace = command.operation.workspace;
    final original = await _reversible(t, command);
    final flow = switch (original.kind) {
      PostingKind.income => CashFlow.income,
      PostingKind.expense => CashFlow.expense,
      _ => throw const AppFailure(
        FailureKind.rejected,
        'ledger.correctionReference',
      ),
    };
    final account = await _postable(
      t,
      command.account,
      workspace,
      command.amount.currency,
      command.date,
    );
    final allocations = await _allocations(
      t,
      workspace,
      flow,
      command.allocations,
    );
    final replacementOperation = _secondary(
      command.operation,
      command.postingId,
    );
    final replacement = flow == CashFlow.income
        ? Posting.income(
            id: command.postingId,
            operation: replacementOperation,
            date: command.date,
            account: account,
            amount: command.amount,
            allocations: allocations,
          )
        : Posting.expense(
            id: command.postingId,
            operation: replacementOperation,
            date: command.date,
            account: account,
            amount: command.amount,
            allocations: allocations,
          );
    final correction = PostingCorrection(
      original: original,
      replacement: replacement,
      reversalId: command.reversalId,
      reversalOperation: _secondary(command.operation, command.reversalId),
      reason: command.reason,
    );
    // A corrected recurring entry still confirms its due date, so the
    // occurrence is not proposed again (feature audit G-03).
    final planning = switch (t) {
      final PlanningTransaction planning => planning,
      _ => null,
    };
    final confirmed = await planning?.confirmationOf(original.id);
    await _savePosting(
      t,
      correction.reversal,
      await t.postingMetadata(original.id),
    );
    await _savePosting(
      t,
      replacement,
      await _metadata(
        t,
        workspace,
        command.tags,
        command.merchant,
        homeValue: command.homeValue,
        currency: command.amount.currency,
      ),
    );
    if (planning != null && confirmed != null) {
      final (templateId, dueDate) = confirmed;
      await planning.saveConfirmation(templateId, dueDate, replacement.id);
      await t.appendEvent(
        id: PublicId.generate(),
        workspace: workspace,
        kind: 'recurring.confirmed',
        payload: jsonEncode({
          'templateId': templateId.value,
          'dueDate': dueDate.toString(),
          'postingId': replacement.id.value,
        }),
      );
    }
    // The note travels with the entry it describes (feature audit G-15).
    final note = await t.noteOf(original.id);
    if (note.text.isNotEmpty) {
      await _saveNote(t, workspace, replacement.id, EntryNote(1, note.text));
    }
    return replacement.id;
  }

  Future<PublicId> _correctTransfer(T t, CorrectTransfer command) async {
    await _requireNewPosting(t, command.postingId);
    await _requireNewPosting(t, command.reversalId);
    final workspace = command.operation.workspace;
    final original = await _reversible(t, command);
    if (original.kind != PostingKind.transfer) {
      throw const AppFailure(
        FailureKind.rejected,
        'ledger.correctionReference',
      );
    }
    final received = command.received ?? command.principal;
    final replacement = Posting.transfer(
      id: command.postingId,
      operation: _secondary(command.operation, command.postingId),
      date: command.date,
      source: await _postable(
        t,
        command.source,
        workspace,
        command.principal.currency,
        command.date,
      ),
      destination: await _postable(
        t,
        command.destination,
        workspace,
        received.currency,
        command.date,
      ),
      principal: command.principal,
      received: command.received,
      fee: command.fee,
      allocations: await _allocations(
        t,
        workspace,
        CashFlow.expense,
        command.feeAllocations,
      ),
    );
    final correction = PostingCorrection(
      original: original,
      replacement: replacement,
      reversalId: command.reversalId,
      reversalOperation: _secondary(command.operation, command.reversalId),
      reason: command.reason,
    );
    await _savePosting(t, correction.reversal, PostingMetadata.none);
    await _savePosting(t, replacement, PostingMetadata.none);
    final note = await t.noteOf(original.id);
    if (note.text.isNotEmpty) {
      await _saveNote(t, workspace, replacement.id, EntryNote(1, note.text));
    }
    return replacement.id;
  }

  Future<int> _note(T t, SetNote command) async {
    final posting = await t.posting(command.postingId);
    if (posting == null ||
        posting.operation.workspace != command.operation.workspace) {
      throw const AppFailure(FailureKind.notFound, 'posting.not-found');
    }
    final note = NoteChange(
      command.postingId,
      command.expectedRevision,
      command.text,
    ).apply(await t.noteOf(command.postingId));
    await _saveNote(t, command.operation.workspace, command.postingId, note);
    return note.revision;
  }

  Future<void> _saveNote(
    T t,
    WorkspaceId workspace,
    PublicId postingId,
    EntryNote note,
  ) async {
    await t.saveNote(postingId, note);
    await t.appendEvent(
      id: PublicId.generate(),
      workspace: workspace,
      kind: 'posting.noted',
      payload: jsonEncode({
        'postingId': postingId.value,
        'revision': note.revision,
        'text': note.text,
      }),
    );
  }

  /// Reverses a posting its card or trade owns, on the posting's own date.
  Future<PublicId> _reverseOwned(
    T t,
    OperationKey operation,
    PublicId reversalId,
    PublicId postingId,
  ) async {
    await _requireNewPosting(t, reversalId);
    final original = await _undoable(
      t,
      operation.workspace,
      postingId,
      owned: true,
    );
    final reversal = Posting.reversal(
      id: reversalId,
      operation: operation,
      date: original.date,
      original: original,
      reason: 'voided',
      tradeVoid: true,
    );
    await _savePosting(t, reversal, await t.postingMetadata(original.id));
    return reversal.id;
  }

  /// The checks every undo path shares: the posting exists in this
  /// workspace, is not reversed yet, is not owned by a card or trade, has
  /// no active refunds, and touches no closed account.
  Future<Posting> _reversible(T t, Command<Object?> command) {
    final originalId = switch (command) {
      ReversePosting(:final originalId) => originalId,
      DeletePosting(:final originalId) => originalId,
      CorrectCashFlow(:final originalId) => originalId,
      CorrectTransfer(:final originalId) => originalId,
      _ => throw StateError('Not an undo command.'),
    };
    return _undoable(t, command.operation.workspace, originalId);
  }

  /// [owned] is true when the card or trade that owns the posting undoes it
  /// itself; everyone else is refused.
  Future<Posting> _undoable(
    T t,
    WorkspaceId workspace,
    PublicId originalId, {
    bool owned = false,
  }) async {
    final original = await t.posting(originalId);
    if (original == null || original.operation.workspace != workspace) {
      throw const AppFailure(FailureKind.notFound, 'posting.not-found');
    }
    if (await t.isReversed(original.id)) {
      throw const AppFailure(FailureKind.conflict, 'posting.already-reversed');
    }
    if (!owned && await t.isLocked(original.id)) {
      throw const AppFailure(FailureKind.rejected, 'posting.owned-elsewhere');
    }
    if ((await _activeRefunds(t, original.id)).isNotEmpty) {
      throw const AppFailure(FailureKind.rejected, 'posting.has-refunds');
    }
    // A closed account must keep its zero balance.
    for (final leg in original.legs) {
      final account = await _account(t, leg.account.id);
      if (account.state == AccountState.closed) {
        throw const AppFailure(FailureKind.rejected, 'account.unavailable');
      }
    }
    return original;
  }
}
