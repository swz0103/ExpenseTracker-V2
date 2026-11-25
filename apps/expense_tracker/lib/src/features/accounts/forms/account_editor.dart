import 'package:core/foundation_values.dart' show Currency;
import 'package:core/money/amount_parser.dart' show parseAmount;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;

import '../../../core/design_system/dialogs.dart';
import '../../../../design_system/display/amount.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/widgets/icons.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/widgets/calculator.dart';
import '../../../core/widgets/pickers.dart';
import '../../../core/widgets/problem_note.dart';

import '../model/account_form.dart';
import '../ui/account_card.dart' show cardKindLabel;
import '../ui/accounts.dart' show walletKinds;
import '../../../core/widgets/shown_amounts.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/formatting/words.dart';
import '../../../core/messages/done_messages.dart';
import '../../../core/messages/flow_messages.dart';
import '../../../core/messages/trade_messages.dart';
import '../../../core/messages/trash_messages.dart';

import 'loan_cards.dart';

part 'loan_fields.dart';
part 'loan_blocks.dart';
part 'account_editor_state.dart';
part 'account_editor_edit_card.dart';

/// True when [ledger] has an open account, after offering to add one if
/// it has none: entries, imports and recurring items all need one.
Future<bool> ensureAccount(BuildContext context, Ledger ledger) async {
  if (ledger.accounts.open.isNotEmpty) return true;
  final add = await confirm(context, '先新增一個帳戶，才能記帳', '新增帳戶');
  if (add && context.mounted) await editAccount(context, ledger);
  return ledger.accounts.open.isNotEmpty && context.mounted;
}

/// Opens the account form: a new account, or [account] to change. Saving
/// writes to [ledger] directly. True when the account was deleted or
/// archived, so the page showing it should go back. A new one opens in
/// [currency] when given.
Future<bool> editAccount(
  BuildContext context,
  Ledger ledger, {
  Account? account,
  String? currency,
}) async {
  final gone = await showSheet<bool>(
    context,
    (_) => _AccountEditor(ledger: ledger, account: account, currency: currency),
  );
  return gone ?? false;
}

/// Opens the form of a loan: a new one, from 代墊與借貸, or [loan] to
/// change. True when it was deleted or archived.
Future<bool> editLoan(
  BuildContext context,
  Ledger ledger, {
  Account? loan,
}) async {
  final gone = await showSheet<bool>(
    context,
    (_) =>
        _AccountEditor(ledger: ledger, account: loan, kind: AccountKind.loan),
  );
  return gone ?? false;
}

class _AccountEditor extends StatefulWidget {
  const _AccountEditor({
    required this.ledger,
    this.account,
    this.kind,
    this.currency,
  });

  final Ledger ledger;
  final Account? account;

  /// The currency a new account opens in; the home one when null.
  final String? currency;

  /// The kind a new account opens as.
  final AccountKind? kind;

  @override
  State<_AccountEditor> createState() => _AccountEditorState();
}

/// Archives [account], settling it first when something is left once what
/// is dated ahead has come: the account picked, of its currency, takes
/// the balance or pays the debt ([AccountForm.settlement], D120). With no
/// such account, says so and offers to add one, or to keep [account] as
/// it is. Told with 復原, which takes the settlement back too (D82).
/// Whether it was archived; a refusal of the ledger is said. [left] is
/// what is left, when the caller has just worked it out.
Future<bool> settleAndArchive(
  BuildContext context,
  Ledger ledger,
  Account account, {
  int? left,
}) async {
  left ??= ledger.balanceService.finalBalance(account.id);
  Entry? settlement;
  if (left != 0) {
    final into = await _settleInto(context, ledger, account, owing: left < 0);
    if (into == null || !context.mounted) return false;
    final made = AccountForm.settlement(ledger, account, into);
    if (!refusalShown(
      context,
      () => ledger.entryCommands.addSettlement(made, account.id),
    )) {
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
