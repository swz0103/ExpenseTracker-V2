part of 'compose_form.dart';

// A transfer: its two ends, and what each holds once it is made.

extension TransferFields on ComposeForm {
  /// What the account paid from holds once the transfer is made: less
  /// the amount and any fee.
  int get fromAfter =>
      ledger.balanceService.balance(account) - amount - (takesFee ? fee : 0);

  /// What the account paid into holds once the transfer is made: more
  /// what arrives, in its own currency when they differ.
  int get toAfter =>
      ledger.balanceService.balance(to) +
      (crossing ? receivedValue ?? 0 : amount);

  /// Pays from [id] instead; an amount received was in the other end's
  /// terms, so it is worked out again.
  void setFrom(String id) {
    account = id;
    received = null;
  }

  /// Pays into [id] instead, as [setFrom] does.
  void setTo(String id) {
    to = id;
    received = null;
  }
}
