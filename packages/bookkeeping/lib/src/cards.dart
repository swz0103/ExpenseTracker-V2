part of 'bookkeeping.dart';

/// Card records stored next to the ledger. Charges and payments link to the
/// posting they produced; that posting is then locked against reversal.
abstract interface class CardTransaction implements BookkeepingTransaction {
  Future<CreditCardTerms?> cardTerms(PublicId cardId);

  Future<void> saveCardTerms(CreditCardTerms terms);

  Future<CardCharge?> cardCharge(PublicId chargeId);

  Future<void> saveCardCharge(CardCharge charge);

  Future<void> saveCardPayment(CardPayment payment);

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

  Future<CommandOutcome<PublicId>> authorize(AuthorizeCardCharge command) =>
      _runner.run(command, (t) => _guard(() => _authorize(t, command)));

  Future<CommandOutcome<PublicId>> post(PostCardCharge command) =>
      _runner.run(command, (t) => _guard(() => _post(t, command)));

  Future<CommandOutcome<PublicId>> pay(PayCard command) =>
      _runner.run(command, (t) => _guard(() => _pay(t, command)));

  Future<CommandOutcome<int>> planInstallments(PlanInstallments command) =>
      _runner.run(command, (t) => _guard(() => _plan(t, command)));

  Future<int> _setTerms(T t, SetCardTerms command) async {
    final card = await _card(t, command.cardId, command.operation);
    final current = await t.cardTerms(card.id);
    if ((current?.version ?? 0) != command.expectedVersion) {
      throw const AppFailure(FailureKind.conflict, 'card.versionConflict');
    }
    final terms = CreditCardTerms(
      workspace: card.workspace,
      cardId: card.id,
      currency: card.currency,
      closingDay: command.closingDay,
      dueDay: command.dueDay,
      limit: command.limit,
      version: command.expectedVersion + 1,
    );
    await t.saveCardTerms(terms);
    await _event(t, card.workspace, 'card.terms-set', {
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

  Future<PublicId> _post(T t, PostCardCharge command) async {
    final workspace = command.operation.workspace;
    final card = await _card(t, command.card.id, command.operation);
    await _books._requireNewPosting(t, command.postingId);
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
    await t.saveCardCharge(posted);
    await _books._savePosting(t, posting, metadata);
    await _event(t, workspace, 'card.posted', _charge(posted));
    return posting.id;
  }

  Future<PublicId> _pay(T t, PayCard command) async {
    final workspace = command.operation.workspace;
    final card = await _card(t, command.card.id, command.operation);
    final terms = await _terms(t, card.id);
    final cycle = terms.scheduledCycleFor(command.statementClose);
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
    await t.saveCardPayment(payment);
    await _books._savePosting(t, posting, PostingMetadata.none);
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
    final plan = CardInstallmentSchedule(
      purchaseEventId: charge.ledgerEventId!,
      workspace: charge.workspace,
      cardId: charge.cardId,
      principal: charge.settledAmount!,
      fixedFee: command.fixedFee,
      firstScheduledClose: terms.scheduledCycleFor(charge.postedOn!).closesOn,
      closingDay: terms.closingDay,
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
