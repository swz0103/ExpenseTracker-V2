import 'package:flutter/material.dart';

import '../../../core/look/dialogs.dart';
import '../../../core/look/figures.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/ui/calculator.dart';
import '../model/reconcile.dart';

/// 對帳: asks what [account] holds (or, for a card or loan, owes) as the
/// bank or the wallet shows it, and records the difference as an
/// adjustment dated today, once the person agrees.
Future<void> reconcileAccount(
  BuildContext context,
  Ledger ledger,
  Account account,
) async {
  final debt = account.kind.isDebt;
  final book = shownBalance(ledger, account);
  final counted = await showCalculator(
    context,
    title: debt ? '實際欠款' : '實際餘額',
    initial: book,
    color: Hue.accent,
  );
  if (counted == null || !context.mounted) return;
  final entry = reconcile(ledger, account, counted);
  if (entry == null) {
    showNote(context, '帳上金額一致，不用調整');
    return;
  }
  final spent = entry.type == EntryType.expense;
  final ok = await confirm(
    context,
    '帳上 ${groupDigits(book)}，實際 ${groupDigits(counted)}，'
        '差 ${groupDigits(entry.amount)}。'
        '記一筆「$reconcileNote」${spent ? '支出' : '收入'}'
        '（${entry.category}）？',
    '記下',
  );
  if (!ok || !context.mounted) return;
  ledger.add(entry);
  showNote(context, '已記下對帳調整 ${spent ? '−' : '+'}${groupDigits(entry.amount)}');
}
