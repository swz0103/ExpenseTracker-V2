part of 'ledger_store.dart';

/// Credit-card reads for the screens: terms, statements, holds, credit
/// and installments.
extension CardQueries on LedgerStore {
  CreditCardTerms? cardTerms(PublicId cardId) =>
      _readTerms(_store.select, cardId);

  /// The statement whose cycle contains [date], from posted charges and
  /// payments. Pending authorizations are only counted.
  CardStatement statement(PublicId cardId, BusinessDate date) {
    final terms = cardTerms(cardId);
    if (terms == null) throw StateError('Card has no terms.');
    return CardStatement.calculate(
      terms: terms,
      cycle: terms.cycleFor(date),
      charges: _cardCharges(cardId),
      payments: _cardPayments(cardId),
      plans: _cardPlans(cardId),
    );
  }

  /// The posted charges, installments and payments behind the statement
  /// whose cycle contains [date].
  CardStatementItems statementItems(PublicId cardId, BusinessDate date) {
    final terms = cardTerms(cardId);
    if (terms == null) throw StateError('Card has no terms.');
    return CardStatementItems.select(
      cycle: terms.cycleFor(date),
      charges: _cardCharges(cardId),
      payments: _cardPayments(cardId),
      plans: _cardPlans(cardId),
    );
  }

  /// Authorizations that have not posted yet, oldest first.
  List<CardCharge> pendingCharges(PublicId cardId) {
    final pending = [
      for (final charge in _cardCharges(cardId))
        if (!charge.isPosted) charge,
    ];
    return pending..sort((a, b) => a.authorizedOn.compareTo(b.authorizedOn));
  }

  /// What can still be charged to the card; null when it has no limit.
  Money? availableCredit(PublicId cardId) {
    final terms = cardTerms(cardId);
    if (terms == null) throw StateError('Card has no terms.');
    return remainingCredit(
      terms: terms,
      charges: _cardCharges(cardId),
      payments: _cardPayments(cardId),
    );
  }

  List<CardCharge> _cardCharges(PublicId cardId) {
    final rows = _store.select(
      'SELECT payload FROM card_charges WHERE card_id = ? AND released = 0',
      [cardId.value],
    );
    return [
      for (final row in rows) CardRecords.readCharge(_json(row['payload'])),
    ];
  }

  List<CardPayment> _cardPayments(PublicId cardId) {
    final rows = _store.select(
      'SELECT payload FROM card_payments WHERE card_id = ? AND voided = 0',
      [cardId.value],
    );
    return [
      for (final row in rows) CardRecords.readPayment(_json(row['payload'])),
    ];
  }

  List<CardInstallmentSchedule> _cardPlans(PublicId cardId) {
    const codec = CardInstallmentScheduleCodec();
    final rows = _store.select(
      'SELECT payload FROM card_installment_plans WHERE card_id = ?',
      [cardId.value],
    );
    return [for (final row in rows) codec.decode(row['payload']! as String)];
  }

  /// Forecast installments for the purchase posted as [postingId].
  List<CardInstallment> installments(PublicId postingId) {
    final plan = _readPlan(_store.select, postingId);
    return plan == null ? const [] : plan.installments;
  }
}
