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
}
