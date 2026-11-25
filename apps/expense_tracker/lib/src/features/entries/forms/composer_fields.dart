import 'package:flutter/material.dart';

import '../../../../design_system/display/amount.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/widgets/icons.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../model/compose_form.dart';
import '../../../core/messages/installment_messages.dart';
import '../../../../design_system/display/date.dart';
import '../../../core/design_system/spacing.dart';
import 'compose_cards.dart';
import 'extras_fields.dart';
import 'investment_fields.dart';
import 'lend_fields.dart';
import 'form_rows.dart';
import 'note_field.dart';
import '../../../core/formatting/words.dart';
import 'composer_state.dart';
import 'composer_pickers.dart';
import 'composer_amount.dart';

/// The form's fields, one builder each, by kind of entry. Each kind's
/// list starts at the amount (a trade's at what is traded).
extension ComposerFields on ComposerState {
  /// Two cards side by side, such as the account and the day.
  Widget pairCards(Widget left, Widget right) => Padding(
    padding: const EdgeInsets.only(top: Space.s3),
    child: Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: Space.s2),
        Expanded(child: right),
      ],
    ),
  );

  Widget accountCard(String label) {
    final account = composerLedger.account(form.account);
    return PickCard(
      icon: accountIcon(account),
      label: label,
      value: account.name,
      onTap: viewing
          ? null
          : () async {
              final picked = await chooseAccount(label, form.account);
              if (picked == null) return;
              update(() {
                form.account = picked;
                form.home = null;
              });
            },
    );
  }

  Widget dateCard() {
    final day = formatMd(form.date);
    return PickCard(
      icon: Glyph.calendar,
      label: Words.date,
      value: form.date == composerLedger.today
          ? '今天 $day'
          : '$day ${formatE(form.date)}',
      onTap: viewing ? null : chooseDate,
    );
  }

  /// The note, folded to one line until opened or written in.
  Widget _noteRow() => NoteRow(
    controller: note,
    viewing: viewing,
    open: form.more,
    onOpen: () => update(() => form.more = true),
  );

  List<Widget> kindFields() {
    if (form.refunded != null) {
      return [
        amountHero(),
        pairCards(accountCard('退回到'), dateCard()),
        _noteRow(),
      ];
    }
    switch (form.mode) {
      case ComposeMode.expense || ComposeMode.income:
        final expense = form.mode == ComposeMode.expense;
        final parts = form.parts;
        return [
          amountHero(
            under: form.lending
                ? LendFields(this).row()
                : parts == null
                ? UsualFields(this).spending()
                : CategoryFields(this).splitState(),
          ),
          if (parts != null)
            AllocationBar(
              parts: [
                for (final (name, value) in parts)
                  (composerLedger.category(name), value),
              ],
              onTap: editPart,
            ),
          CategoryFields(this).row(expense: expense),
          pairCards(accountCard(expense ? '付款帳戶' : '收款帳戶'), dateCard()),
          if (form.foreign) CurrencyFields(this).home(),
          if (form.onCard)
            Padding(
              padding: const EdgeInsets.only(top: Space.s2),
              child: FigureCard(
                color: color,
                icon: Glyph.card,
                label: '分期付款',
                value: form.installments < 2
                    ? '不分期'
                    : installmentPlan(form.amount, form.installments),
                size: TextSize.body,
                onTap: chooseInstallments,
              ),
            ),
          ExtrasFields(this).build(expense: expense),
        ];
      case ComposeMode.transfer:
        return [
          amountHero(under: UsualFields(this).transfers()),
          _ends(),
          if (form.crossing) CurrencyFields(this).received(),
          if (!form.takesFee)
            Padding(
              padding: const EdgeInsets.only(top: Space.s3),
              child: dateCard(),
            )
          else
            pairCards(
              form.takesFee
                  ? PickCard(
                      icon: Glyph.coins,
                      label: Words.fee,
                      value: '手續費 ${groupDigits(form.fee)}',
                      valueColor: form.fee > 0
                          ? AppColors.negative
                          : AppColors.ink,
                      onTap: () async {
                        final value = await askAmount(Words.fee, form.fee);
                        if (value != null) {
                          update(() => form.fee = value);
                        }
                      },
                    )
                  : const SizedBox.shrink(),
              dateCard(),
            ),
          _noteRow(),
        ];
      case ComposeMode.lend:
        return LendFields(this).build();
      case ComposeMode.investment:
        return InvestmentFields(this).build(context);
    }
  }

  /// The two accounts of a transfer side by side, each with what it will
  /// hold afterwards, and between them the arrow that turns them round.
  Widget _ends() => TransferEnds(
    ledger: composerLedger,
    from: composerLedger.account(form.account),
    to: composerLedger.account(form.to),
    amount: form.amount,
    fromAfter: form.fromAfter,
    toAfter: form.toAfter,
    onPickFrom: () async {
      final picked = await chooseAccount('轉出帳戶', form.account);
      if (picked != null) update(() => form.setFrom(picked));
    },
    onPickTo: () async {
      final picked = await chooseAccount('轉入帳戶', form.to);
      if (picked != null) update(() => form.setTo(picked));
    },
    onSwap: () => update(form.swapEnds),
  );
}
