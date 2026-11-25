import 'package:flutter/material.dart';

import '../../../../design_system/display/amount.dart';
import '../../../core/ledger/ledger.dart';
import '../model/compose_form.dart';
import '../../../core/widgets/shown_amounts.dart';
import 'compose_widgets.dart';
import '../../../core/formatting/words.dart';
import 'composer_state.dart';
import 'composer_pickers.dart';

// The amount on top: its label and the block it stands in.

extension ComposerAmount on ComposerState {
  /// What a screen reader calls the amount, and the keypad's title.
  String get _amountLabel => switch (form.type) {
    _ when form.refunded != null => '退款金額',
    _ when form.mode == ComposeMode.lend => form.back ? '還款金額' : '代墊金額',
    EntryType.transfer => '轉出金額',
    EntryType.dividend when form.reducing => '退還股款',
    EntryType.dividend => '股息金額',
    _ => Words.amount,
  };

  /// The amount in the middle of the form, [under] it such as 常用.
  Widget amountHero({Widget? under, String? unit}) {
    final refunded = form.refunded;
    final most = refunded == null
        ? 0
        : composerLedger.entryQueryService.refundable(refunded) +
              (widget.entry?.amount ?? 0);
    return AmountHero(
      label: _amountLabel,
      // Beside its currency the amount is figures only; beside a word
      // such as 實收 it keeps its currency.
      unit: unit ?? currencyLabel(form.currency),
      value:
          '${form.sign}${unit == null ? figuresIn(form.amount, form.currency) : amountIn(form.amount, form.currency)}',
      spoken: spokenAmount(
        form.amount,
        currency: form.currency,
        sense: form.amount == 0
            ? AmountSense.plain
            : form.refunded != null || (form.editing?.isRefund ?? false)
            ? AmountSense.refund
            : switch (form.type) {
                EntryType.expense || EntryType.buy => AmountSense.spending,
                EntryType.transfer => AmountSense.plain,
                _ => AmountSense.income,
              },
      ),
      color: color,
      empty: form.amount == 0,
      // Only while editing: an entry looked at shows no calculator.
      onTap: viewing ? null : typeAmount,
      sub: refunded == null
          ? null
          : '最多可退 ${composerLedger.moneyIn(most, form.currency)}',
      under: under,
    );
  }
}
