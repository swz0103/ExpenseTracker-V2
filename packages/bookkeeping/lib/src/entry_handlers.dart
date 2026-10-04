part of 'bookkeeping.dart';

/// Income, expense, transfers and refunds.
extension _Entries<T extends BookkeepingTransaction> on Bookkeeping<T> {
  Future<PublicId> _cashFlow(T t, RecordCashFlow command) async {
    await _requireNewPosting(t, command.postingId);
    final workspace = command.operation.workspace;
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
      command.flow,
      command.allocations,
    );
    final metadata = await _metadata(
      t,
      workspace,
      command.tags,
      command.merchant,
      homeValue: command.homeValue,
      currency: command.amount.currency,
    );
    final posting = switch (command.flow) {
      CashFlow.income => Posting.income(
        id: command.postingId,
        operation: command.operation,
        date: command.date,
        account: account,
        amount: command.amount,
        allocations: allocations,
      ),
      CashFlow.expense => Posting.expense(
        id: command.postingId,
        operation: command.operation,
        date: command.date,
        account: account,
        amount: command.amount,
        allocations: allocations,
      ),
    };
    await _savePosting(t, posting, metadata);
    return posting.id;
  }

  Future<PublicId> _transfer(T t, RecordTransfer command) async {
    await _requireNewPosting(t, command.postingId);
    final workspace = command.operation.workspace;
    final received = command.received ?? command.principal;
    final posting = Posting.transfer(
      id: command.postingId,
      operation: command.operation,
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
    await _savePosting(t, posting, PostingMetadata.none);
    return posting.id;
  }

  Future<PublicId> _refund(
    T t,
    RecordRefund command, {
    bool owned = false,
  }) async {
    await _requireNewPosting(t, command.postingId);
    final workspace = command.operation.workspace;
    final original = await t.posting(command.originalId);
    if (original == null || original.operation.workspace != workspace) {
      throw const AppFailure(FailureKind.notFound, 'posting.not-found');
    }
    if (original.kind != PostingKind.expense) {
      throw const AppFailure(FailureKind.rejected, 'ledger.refundReference');
    }
    if (await t.isReversed(original.id)) {
      throw const AppFailure(FailureKind.rejected, 'posting.already-reversed');
    }
    if (!owned && await t.isLocked(original.id)) {
      throw const AppFailure(FailureKind.rejected, 'posting.owned-elsewhere');
    }
    // The remaining refund authority is replayed from earlier refunds.
    var budget = RefundBudget(
      originalId: original.id,
      originalDate: original.date,
      amount: original.reportExpense,
      allocations: original.allocations,
    );
    for (final earlier in await _activeRefunds(t, original.id)) {
      budget = budget.consume(
        amount: -earlier.reportExpense,
        date: earlier.date,
        allocations: earlier.allocations,
      );
    }
    final allocations = [
      for (final share in command.allocations)
        Allocation(
          share.categoryId,
          share.amount,
          expectedCategoryVersion: share.expectedVersion,
        ),
    ];
    budget.consume(
      amount: command.amount,
      date: command.date,
      allocations: allocations,
    );
    final received = command.received ?? command.amount;
    final posting = Posting.refund(
      id: command.postingId,
      operation: command.operation,
      date: command.date,
      account: await _postable(
        t,
        command.account,
        workspace,
        received.currency,
        command.date,
        card: owned,
      ),
      originalId: original.id,
      amount: command.amount,
      received: command.received,
      allocations: allocations,
    );
    // A foreign refund is worth its share of the purchase's home value.
    final metadata = await t.postingMetadata(original.id);
    final home = metadata.homeValue;
    final share = home == null
        ? null
        : Money.quantizeRatio(
            homeCurrency,
            home.minorUnits * command.amount.minorUnits,
            original.reportExpense.minorUnits *
                BigInt.from(10).pow(homeCurrency.scale),
          );
    final value = share == null || share.minorUnits == BigInt.zero
        ? null
        : share;
    await _savePosting(t, posting, metadata.withHomeValue(value));
    return posting.id;
  }

  Future<List<Posting>> _activeRefunds(T t, PublicId expenseId) async => [
    for (final refund in await t.refundsOf(expenseId))
      if (!await t.isReversed(refund.id)) refund,
  ];
}
