part of 'account_editor.dart';

/// Archives [account], settling it first when something is left once what
/// is dated ahead has come: the account picked, of its currency, takes
/// the balance or pays the debt ([AccountForm.settlement], D120). With no
/// such account, says so and offers to add one, or to keep [account] as
/// it is. Told with 復原, which takes the settlement back too (D82).
/// Whether it was archived; a refusal of the ledger is said.
Future<bool> settleAndArchive(
  BuildContext context,
  Ledger ledger,
  Account account,
) async {
  final left = ledger.balanceService.finalBalance(account.id);
  Entry? settlement;
  if (left != 0) {
    final into = await _settleInto(context, ledger, account, owing: left < 0);
    if (into == null || !context.mounted) return false;
    final made = AccountForm.settlement(ledger, account, into);
    if (!refusalShown(context, () => ledger.entryCommands.add(made))) {
      return false;
    }
    // The entry as the book holds it, the one its undo takes back.
    settlement = ledger.entries.byId(made.id);
  }
  Undo? undo;
  final archived = refusalShown(
    context,
    () => undo = ledger.accountCommands.setArchived(account.id, archived: true),
  );
  if (!archived) {
    if (settlement != null) ledger.entryCommands.takeBack([settlement]);
    return false;
  }
  if (undo case final undo?) {
    showUndo(context, DoneWords.archived(account.name), () {
      undo();
      if (settlement != null) ledger.entryCommands.takeBack([settlement]);
    });
  }
  return true;
}

/// The account [account]'s balance goes to, or its debt is paid from
/// ([owing]): picked among the open ones of its currency. With none,
/// offers to add one (and picks again) or to keep [account]; null when
/// the person keeps it or picks nothing.
Future<String?> _settleInto(
  BuildContext context,
  Ledger ledger,
  Account account, {
  required bool owing,
}) async {
  for (;;) {
    if (!context.mounted) return null;
    final options = accountOptions(
      ledger,
      currency: account.currency,
      // Money is held there: not a debt, nor another person.
      where: (a) =>
          a.id != account.id &&
          !a.kind.isDebt &&
          a.kind != AccountKind.receivable,
    );
    if (options.isNotEmpty) {
      return pickOption<String>(
        context,
        title: owing ? SettleWords.payFrom : SettleWords.moveTo,
        selected: null,
        columns: 3,
        options: options,
      );
    }
    final add = await confirm(
      context,
      SettleWords.noAccount(currencyName(account.currency)),
      SettleWords.addAccount,
      body: SettleWords.noAccountBody(account.name),
      cancel: SettleWords.keep,
    );
    if (!add || !context.mounted) return null;
    await editAccount(context, ledger, currency: account.currency);
  }
}
