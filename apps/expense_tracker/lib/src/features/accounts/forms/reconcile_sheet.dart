import 'package:flutter/material.dart';

import '../../../core/design_system/dialogs.dart';
import '../../../../design_system/display/amount.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/widgets/calculator.dart';
import '../model/reconcile.dart';
import '../../../core/formatting/words.dart';

/// 對帳: asks what [account] holds (or, for a card or loan, owes) as the
/// bank or the wallet shows it, and records the difference as an
/// adjustment dated today, once the person agrees.
Future<void> reconcileAccount(
  BuildContext context,
  Ledger ledger,
  Account account,
) async {
  final debt = account.kind.isDebt;
  final book = shownBalance(ledger.balanceService, account);
  final counted = await showCalculator(
    context,
    title: debt ? '實際欠款' : '實際餘額',
    initial: book,
    color: AppColors.accent,
  );
  if (counted == null || !context.mounted) return;
  final entry = reconcile(
    ledger.balanceService,
    account,
    counted,
    id: ledger.newId(),
    today: ledger.today,
  );
  if (entry == null) {
    showNote(context, '帳上金額一致，不用調整');
    return;
  }
  final spent = entry.type == EntryType.expense;
  final ok = await confirm(
    context,
    '帳上 ${groupDigits(book)}，實際 ${groupDigits(counted)}，'
        '差 ${groupDigits(entry.amount)}。'
        '記一筆「$reconcileNote」${spent ? Words.expense : Words.income}'
        '（${entry.category}）？',
    '記下',
  );
  if (!ok || !context.mounted) return;
  ledger.entryCommands.add(entry);
  final note = '已記下對帳調整 ${spent ? '−' : '+'}${groupDigits(entry.amount)}';
  showNote(
    context,
    note,
    spoken: readOut(
      note,
      entry.amount,
      sense: spent ? AmountSense.spending : AmountSense.income,
    ),
  );
}
