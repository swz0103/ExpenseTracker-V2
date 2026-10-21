part of 'ledger_store.dart';

/// Credit-card reads for the screens: terms, statements and installments.
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
