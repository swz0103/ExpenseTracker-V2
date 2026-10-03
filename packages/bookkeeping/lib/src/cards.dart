part of 'bookkeeping.dart';

/// Card records stored next to the ledger. Charges and payments link to the
/// posting they produced; that posting is then locked against reversal.
abstract interface class CardTransaction implements BookkeepingTransaction {
  Future<CreditCardTerms?> cardTerms(PublicId cardId);

  Future<void> saveCardTerms(CreditCardTerms terms);

  Future<CardCharge?> cardCharge(PublicId chargeId);

  Future<void> saveCardCharge(CardCharge charge);

  /// True once a pending authorization was released without posting.
  Future<bool> isReleased(PublicId chargeId);

  Future<void> releaseCardCharge(PublicId chargeId);

  /// Takes a posted charge off the statement once its posting has been
  /// reversed; [isReleased] then reports true for it.
  Future<void> voidCardCharge(PublicId chargeId);

  Future<void> saveCardPayment(CardPayment payment);

  Future<CardPayment?> cardPayment(PublicId paymentId);

  Future<bool> isPaymentVoided(PublicId paymentId);

  Future<void> voidCardPayment(PublicId paymentId);

  Future<CardInstallmentSchedule?> installmentPlan(PublicId purchaseEventId);

  Future<void> saveInstallmentPlan(CardInstallmentSchedule plan);
}

/// Credit card commands. Statements are read models computed from posted
/// charges and payments; spending is the original purchase, never the bill.
final class CardBook<T extends CardTransaction> {
  CardBook(this._books);

  final Bookkeeping<T> _books;

  CommandRunner<T> get _runner => _books._runner;

  Future<CommandOutcome<int>> setTerms(SetCardTerms command) =>
      _runner.run(command, (t) => _guard(() => _setTerms(t, command)));

  Future<CommandOutcome<int>> overrideCycle(OverrideCardCycle command) =>
      _runner.run(command, (t) => _guard(() => _overrideCycle(t, command)));

  Future<CommandOutcome<PublicId>> authorize(AuthorizeCardCharge command) =>
      _runner.run(command, (t) => _guard(() => _authorize(t, command)));

  Future<CommandOutcome<PublicId>> post(PostCardCharge command) =>
      _runner.run(command, (t) => _guard(() => _post(t, command)));

  Future<CommandOutcome<PublicId>> release(ReleaseAuthorization command) =>
      _runner.run(command, (t) => _guard(() => _release(t, command)));

  Future<CommandOutcome<PublicId>> pay(PayCard command) =>
      _runner.run(command, (t) => _guard(() => _pay(t, command)));

  Future<CommandOutcome<int>> planInstallments(PlanInstallments command) =>
      _runner.run(command, (t) => _guard(() => _plan(t, command)));

  Future<CommandOutcome<PublicId>> refund(RefundCardCharge command) =>
      _runner.run(command, (t) => _guard(() => _refund(t, command)));

  Future<CommandOutcome<PublicId>> voidCharge(VoidCardCharge command) =>
      _runner.run(command, (t) => _guard(() => _voidCharge(t, command)));

  Future<CommandOutcome<PublicId>> voidPayment(VoidCardPayment command) =>
      _runner.run(command, (t) => _guard(() => _voidPayment(t, command)));

  Future<PublicId> _refund(T t, RefundCardCharge command) async {
    final workspace = command.operation.workspace;
    final card = await _card(t, command.card.id, command.operation);
    final original = await t.cardCharge(command.originalChargeId);
    if (original == null || original.cardId != card.id) {
      throw const AppFailure(FailureKind.notFound, 'card.charge-not-found');
    }
    if (original.kind != CardChargeKind.purchase ||
        !original.isPosted ||
        await t.isReleased(original.id)) {
      throw const AppFailure(FailureKind.rejected, 'card.not-posted');
    }
    if (await t.cardCharge(command.refundChargeId) != null) {
      throw const AppFailure(FailureKind.conflict, 'card.charge-exists');
    }
    if (command.amount.currency != card.currency) {
      throw const AppFailure(FailureKind.rejected, 'card.currencyMismatch');
    }
    // A card credit can return the purchase, never its fee.
    var refunded = command.amount;
    final earlier = await _books._activeRefunds(t, original.ledgerEventId!);
    for (final refund in earlier) {
      refunded -= refund.reportExpense;
    }
    if (refunded.minorUnits > original.settledAmount!.minorUnits) {
      throw const AppFailure(FailureKind.rejected, 'ledger.refundLimit');
    }
    final postingId = await _books._refund(
      t,
      RecordRefund(
        operation: command.operation,
        postingId: command.postingId,
        originalId: original.ledgerEventId!,
        account: command.card,
        date: command.postedOn,
        amount: command.amount,
        allocations: command.allocations,
      ),
      owned: true,
    );
    final pending = CardCharge.pending(
      id: command.refundChargeId,
      workspace: workspace,
      cardId: card.id,
      kind: CardChargeKind.refund,
      authorizedOn: command.postedOn,
      authorizedAmount: command.amount,
      originalChargeId: original.id,
    );
    final credit = pending.post(
      postedOn: command.postedOn,
      settledAmount: command.amount,
      fee: Money(card.currency, BigInt.zero),
      ledgerEventId: postingId,
    );
    await t.saveCardCharge(credit);
    await _event(t, workspace, 'card.posted', _charge(credit));
    return postingId;
  }

  Future<PublicId> _voidCharge(T t, VoidCardCharge command) async {
    final workspace = command.operation.workspace;
    final charge = await t.cardCharge(command.chargeId);
    if (charge == null || charge.workspace != workspace) {
      throw const AppFailure(FailureKind.notFound, 'card.charge-not-found');
    }
    if (!charge.isPosted) {
      throw const AppFailure(FailureKind.rejected, 'card.not-posted');
    }
    if (await t.isReleased(charge.id)) {
      throw const AppFailure(FailureKind.conflict, 'card.voided');
    }
    if (charge.kind == CardChargeKind.purchase &&
        await t.installmentPlan(charge.ledgerEventId!) != null) {
      throw const AppFailure(FailureKind.rejected, 'card.has-installments');
    }
    final reversal = await _books._reverseOwned(
      t,
      command.operation,
      command.reversalId,
      charge.ledgerEventId!,
    );
    await t.voidCardCharge(charge.id);
    await _event(t, workspace, 'card.voided', {'chargeId': charge.id.value});
    return reversal;
  }

  Future<PublicId> _voidPayment(T t, VoidCardPayment command) async {
    final workspace = command.operation.workspace;
    final payment = await t.cardPayment(command.paymentId);
    if (payment == null || payment.workspace != workspace) {
      throw const AppFailure(FailureKind.notFound, 'card.payment-not-found');
    }
    if (await t.isPaymentVoided(payment.id)) {
      throw const AppFailure(FailureKind.conflict, 'card.voided');
    }
    final reversal = await _books._reverseOwned(
      t,
      command.operation,
      command.reversalId,
      payment.ledgerEventId,
    );
    await t.voidCardPayment(payment.id);
    await _event(t, workspace, 'card.payment-voided', {
      'paymentId': payment.id.value,
    });
    return reversal;
  }

  Future<int> _setTerms(T t, SetCardTerms command) async {
    final card = await _card(t, command.cardId, command.operation);
    final current = await t.cardTerms(card.id);
    if ((current?.version ?? 0) != command.expectedVersion) {
      throw const AppFailure(FailureKind.conflict, 'card.versionConflict');
    }
    final terms = current == null
        ? CreditCardTerms(
            workspace: card.workspace,
            cardId: card.id,
            currency: card.currency,
            closingDay: command.closingDay,
            dueDay: command.dueDay,
            limit: command.limit,
          )
        : current.reschedule(
            closingDay: command.closingDay,
            dueDay: command.dueDay,
            from: command.effectiveFrom,
            limit: command.limit,
          );
    return _saveTerms(t, terms);
  }

  Future<int> _overrideCycle(T t, OverrideCardCycle command) async {
    final card = await _card(t, command.cardId, command.operation);
    final current = await _terms(t, card.id);
    if (current.version != command.expectedVersion) {
      throw const AppFailure(FailureKind.conflict, 'card.versionConflict');
    }
    final terms = current.overrideCycle(
      scheduledClose: command.scheduledClose,
      closesOn: command.closesOn,
      dueOn: command.dueOn,
    );
    return _saveTerms(t, terms);
  }

  Future<int> _saveTerms(T t, CreditCardTerms terms) async {
    await t.saveCardTerms(terms);
    await _event(t, terms.workspace, 'card.terms-set', {
      'terms': const CreditCardTermsCodec().encode(terms),
    });
    return terms.version;
  }

  Future<PublicId> _authorize(T t, AuthorizeCardCharge command) async {
    final card = await _card(t, command.cardId, command.operation);
    if (await t.cardCharge(command.chargeId) != null) {
      throw const AppFailure(FailureKind.conflict, 'card.charge-exists');
    }
    if (command.amount.currency != card.currency) {
      throw const AppFailure(FailureKind.rejected, 'card.currencyMismatch');
    }
    final charge = CardCharge.pending(
      id: command.chargeId,
      workspace: card.workspace,
      cardId: card.id,
      kind: CardChargeKind.purchase,
      authorizedOn: command.authorizedOn,
      authorizedAmount: command.amount,
    );
    await t.saveCardCharge(charge);
    await _event(t, card.workspace, 'card.authorized', _charge(charge));
    return charge.id;
  }

  Future<PublicId> _release(T t, ReleaseAuthorization command) async {
    final card = await _card(t, command.cardId, command.operation);
    final charge = await t.cardCharge(command.chargeId);
    if (charge == null || charge.cardId != card.id) {
      throw const AppFailure(FailureKind.notFound, 'card.charge-not-found');
    }
    if (charge.isPosted || await t.isReleased(charge.id)) {
      throw const AppFailure(FailureKind.rejected, 'card.not-pending');
    }
    await t.releaseCardCharge(charge.id);
    await _event(t, card.workspace, 'card.released', {
      'chargeId': charge.id.value,
    });
    return charge.id;
  }

  Future<PublicId> _post(T t, PostCardCharge command) async {
    final workspace = command.operation.workspace;
    final card = await _card(t, command.card.id, command.operation);
    await _books._requireNewPosting(t, command.postingId);
    if (await t.isReleased(command.chargeId)) {
      throw const AppFailure(FailureKind.rejected, 'card.released');
    }
    final pending =
        await t.cardCharge(command.chargeId) ??
        CardCharge.pending(
          id: command.chargeId,
          workspace: workspace,
          cardId: card.id,
          kind: CardChargeKind.purchase,
          authorizedOn: command.postedOn,
          authorizedAmount: command.settledAmount,
        );
    if (pending.cardId != card.id || pending.workspace != workspace) {
      throw const AppFailure(FailureKind.rejected, 'card.cardMismatch');
    }
    final posted = pending.post(
      postedOn: command.postedOn,
      settledAmount: command.settledAmount,
      fee: command.fee,
      ledgerEventId: command.postingId,
    );
    final total = command.settledAmount + command.fee;
    final account = await _books._postable(
      t,
      command.card,
      workspace,
      total.currency,
      command.postedOn,
      card: true,
    );
    final posting = Posting.expense(
      id: command.postingId,
      operation: command.operation,
      date: command.postedOn,
      account: account,
      amount: total,
      allocations: await _books._allocations(
        t,
        workspace,
        CashFlow.expense,
        command.allocations,
      ),
    );
    final metadata = await _books._metadata(
      t,
      workspace,
      command.tags,
      command.merchant,
    );
    // The posting first: the charge row refers to it.
    await _books._savePosting(t, posting, metadata);
    await t.saveCardCharge(posted);
    await _event(t, workspace, 'card.posted', _charge(posted));
    return posting.id;
  }

  Future<PublicId> _pay(T t, PayCard command) async {
    final workspace = command.operation.workspace;
    final card = await _card(t, command.card.id, command.operation);
    final terms = await _terms(t, card.id);
    final cycle = terms.cycleFor(command.statementClose);
    if (cycle.closesOn != command.statementClose) {
      throw const AppFailure(FailureKind.rejected, 'card.statement-close');
    }
    await _books._requireNewPosting(t, command.postingId);
    final posting = Posting.transfer(
      id: command.postingId,
      operation: command.operation,
      date: command.postedOn,
      source: await _books._postable(
        t,
        command.source,
        workspace,
        command.amount.currency,
        command.postedOn,
      ),
      destination: await _books._postable(
        t,
        command.card,
        workspace,
        command.amount.currency,
        command.postedOn,
        card: true,
      ),
      principal: command.amount,
    );
    final payment = CardPayment(
      id: command.paymentId,
      workspace: workspace,
      cardId: card.id,
      statementClose: command.statementClose,
      postedOn: command.postedOn,
      amount: command.amount,
      ledgerEventId: posting.id,
    );
    await _books._savePosting(t, posting, PostingMetadata.none);
    await t.saveCardPayment(payment);
    await _event(t, workspace, 'card.paid', CardRecords.payment(payment));
    return posting.id;
  }

  Future<int> _plan(T t, PlanInstallments command) async {
    final charge = await t.cardCharge(command.chargeId);
    if (charge == null || charge.workspace != command.operation.workspace) {
      throw const AppFailure(FailureKind.notFound, 'card.charge-not-found');
    }
    if (!charge.isPosted || charge.kind != CardChargeKind.purchase) {
      throw const AppFailure(FailureKind.rejected, 'card.not-posted');
    }
    if (await t.installmentPlan(charge.ledgerEventId!) != null) {
      throw const AppFailure(FailureKind.conflict, 'card.plan-exists');
    }
    final terms = await _terms(t, charge.cardId);
    final first = terms.cycleFor(charge.postedOn!).scheduledClose;
    final plan = CardInstallmentSchedule(
      purchaseEventId: charge.ledgerEventId!,
      workspace: charge.workspace,
      cardId: charge.cardId,
      principal: charge.settledAmount!,
      fixedFee: command.fixedFee,
      firstScheduledClose: first,
      closingDay: terms.closingDayOn(first),
      count: command.count,
    );
    await t.saveInstallmentPlan(plan);
    await _event(t, charge.workspace, 'card.installments-planned', {
      'plan': const CardInstallmentScheduleCodec().encode(plan),
    });
    return plan.count;
  }

  Future<Account> _card(T t, PublicId id, OperationKey operation) async {
    final account = await _books._account(t, id);
    if (account.workspace != operation.workspace) {
      throw const AppFailure(FailureKind.rejected, 'card.workspaceMismatch');
    }
    if (account.kind != AccountKind.creditCard) {
      throw const AppFailure(FailureKind.rejected, 'card.not-a-card');
    }
    return account;
  }

  Future<CreditCardTerms> _terms(T t, PublicId cardId) async {
    final terms = await t.cardTerms(cardId);
    if (terms == null) {
      throw const AppFailure(FailureKind.rejected, 'card.no-terms');
    }
    return terms;
  }

  Map<String, Object?> _charge(CardCharge charge) => CardRecords.charge(charge);

  Future<void> _event(
    T t,
    WorkspaceId workspace,
    String kind,
    Map<String, Object?> payload,
  ) => t.appendEvent(
    id: PublicId.generate(),
    workspace: workspace,
    kind: kind,
    payload: jsonEncode(payload),
  );
}

/// Versioned JSON for card charges and payments. A charge is rebuilt
/// through `pending` and `post`, so every card rule runs again.
abstract final class CardRecords {
  static const version = 1;

  static Map<String, Object?> charge(CardCharge charge) => {
    'version': version,
    'id': charge.id.value,
    'workspace': charge.workspace.toString(),
    'cardId': charge.cardId.value,
    'kind': charge.kind.name,
    'authorizedOn': charge.authorizedOn.toString(),
    'authorizedAmount': charge.authorizedAmount.toJson(),
    'originalChargeId': charge.originalChargeId?.value,
    'postedOn': charge.postedOn?.toString(),
    'settledAmount': charge.settledAmount?.toJson(),
    'fee': charge.fee?.toJson(),
    'ledgerEventId': charge.ledgerEventId?.value,
  };

  static CardCharge readCharge(Map<String, Object?> json) => decoding(() {
    checkKeys(json, const {
      'version',
      'id',
      'workspace',
      'cardId',
      'kind',
      'authorizedOn',
      'authorizedAmount',
      'originalChargeId',
      'postedOn',
      'settledAmount',
      'fee',
      'ledgerEventId',
    });
    if (json['version'] != version) throw const CodecException('version');
    final original = json['originalChargeId'] as String?;
    final pending = CardCharge.pending(
      id: PublicId.parse(json['id'] as String),
      workspace: WorkspaceId.parse(json['workspace'] as String),
      cardId: PublicId.parse(json['cardId'] as String),
      kind: CardChargeKind.values.byName(json['kind'] as String),
      authorizedOn: BusinessDate.parse(json['authorizedOn'] as String),
      authorizedAmount: _readMoney(json['authorizedAmount']),
      originalChargeId: original == null ? null : PublicId.parse(original),
    );
    final event = json['ledgerEventId'] as String?;
    if (event == null) {
      if (json['postedOn'] != null ||
          json['settledAmount'] != null ||
          json['fee'] != null) {
        throw const CodecException('pending');
      }
      return pending;
    }
    return pending.post(
      postedOn: BusinessDate.parse(json['postedOn'] as String),
      settledAmount: _readMoney(json['settledAmount']),
      fee: _readMoney(json['fee']),
      ledgerEventId: PublicId.parse(event),
    );
  });

  static Map<String, Object?> payment(CardPayment payment) => {
    'version': version,
    'id': payment.id.value,
    'workspace': payment.workspace.toString(),
    'cardId': payment.cardId.value,
    'statementClose': payment.statementClose.toString(),
    'postedOn': payment.postedOn.toString(),
    'amount': payment.amount.toJson(),
    'ledgerEventId': payment.ledgerEventId.value,
  };

  static CardPayment readPayment(Map<String, Object?> json) => decoding(() {
    checkKeys(json, const {
      'version',
      'id',
      'workspace',
      'cardId',
      'statementClose',
      'postedOn',
      'amount',
      'ledgerEventId',
    });
    if (json['version'] != version) throw const CodecException('version');
    return CardPayment(
      id: PublicId.parse(json['id'] as String),
      workspace: WorkspaceId.parse(json['workspace'] as String),
      cardId: PublicId.parse(json['cardId'] as String),
      statementClose: BusinessDate.parse(json['statementClose'] as String),
      postedOn: BusinessDate.parse(json['postedOn'] as String),
      amount: _readMoney(json['amount']),
      ledgerEventId: PublicId.parse(json['ledgerEventId'] as String),
    );
  });

  static Money _readMoney(Object? value) {
    if (value is! Map<String, Object?>) throw const CodecException('money');
    return Money.fromJson(value);
  }
}
