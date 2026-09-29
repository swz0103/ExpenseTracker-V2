part of 'preview_engine.dart';

extension PreviewCards on PreviewEngine {
  Future<List<CreditCardTerms>> savedCreditCards() => _exclusive((epoch) async {
    _require();
    if (!capabilities.creditCards) throw PreviewInvalid();
    final cards = await _session!.creditCardTerms(_workspace!);
    _check(epoch);
    return cards;
  });

  Future<void> reviseCreditCard(
    CreditCardTerms terms,
    OperationId operation, {
    bool disabled = false,
  }) => _exclusive((epoch) async {
    _require();
    if (!capabilities.creditCards || terms.workspace != _workspace) {
      throw PreviewInvalid();
    }
    await _session!.reviseCreditCard(
      terms,
      operation,
      DateTime.now().toUtc(),
      disabled: disabled,
    );
    _check(epoch);
  });

  Future<List<ConfirmedCardStatement>> confirmedCardStatements(
    PublicId cardId,
  ) => _exclusive((epoch) async {
    _require();
    if (!capabilities.cardStatements) throw PreviewInvalid();
    final rows = await _session!.confirmedCardStatements(
      workspace: _workspace!,
      cardId: cardId,
    );
    _check(epoch);
    return rows;
  });

  Future<List<CardUnallocatedPayment>> unallocatedCardPayments(
    PublicId cardId,
  ) => _exclusive((epoch) async {
    _require();
    if (!capabilities.cardStatements) throw PreviewInvalid();
    final rows = await _session!.unallocatedCardPayments(
      workspace: _workspace!,
      cardId: cardId,
    );
    _check(epoch);
    return rows;
  });

  Future<void> confirmCardStatement({
    required PublicId statementId,
    required PublicId cardId,
    required int revision,
    required CardCycle cycle,
    required Money billed,
    required OperationId operation,
  }) => _exclusive((epoch) async {
    _require();
    if (!capabilities.cardStatements) throw PreviewInvalid();
    await _session!.confirmCardStatement(
      workspace: _workspace!,
      statementId: statementId,
      cardId: cardId,
      revision: revision,
      cycle: cycle,
      billed: billed,
      operation: operation,
    );
    _check(epoch);
  });

  Future<void> allocateCardPayment({
    required PublicId paymentEventId,
    required PublicId statementId,
    required int statementRevision,
    required Money amount,
    required OperationId operation,
  }) => _exclusive((epoch) async {
    _require();
    if (!capabilities.cardStatements) throw PreviewInvalid();
    await _session!.allocateCardPayment(
      workspace: _workspace!,
      paymentEventId: paymentEventId,
      statementId: statementId,
      statementRevision: statementRevision,
      amount: amount,
      operation: operation,
    );
    _check(epoch);
  });
}
