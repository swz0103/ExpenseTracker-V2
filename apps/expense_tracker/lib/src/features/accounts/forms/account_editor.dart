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
import '../../../core/widgets/problem_note.dart';
import '../../../core/widgets/pickers.dart';

import '../model/account_form.dart';
import '../ui/account_card.dart' show cardKindLabel;
import '../ui/accounts.dart' show walletKinds;
import '../../../core/widgets/shown_amounts.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/formatting/words.dart';
import '../../../core/messages/done_messages.dart';
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
/// archived, so the page showing it should go back.
Future<bool> editAccount(
  BuildContext context,
  Ledger ledger, {
  Account? account,
}) async {
  final gone = await showSheet<bool>(
    context,
    (_) => _AccountEditor(ledger: ledger, account: account),
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
  const _AccountEditor({required this.ledger, this.account, this.kind});

  final Ledger ledger;
  final Account? account;

  /// The kind a new account opens as.
  final AccountKind? kind;

  @override
  State<_AccountEditor> createState() => _AccountEditorState();
}
