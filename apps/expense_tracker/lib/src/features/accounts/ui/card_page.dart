import 'package:flutter/material.dart';

import '../forms/account_editor.dart';
import '../forms/reconcile_sheet.dart';
import '../model/card_summary.dart';
import 'account_action.dart';
import '../../../core/widgets/pickers.dart';
import '../../../core/formatting/figures.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/widgets/icons.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/widgets/entry_tile.dart';
import '../../../core/nav.dart';
import '../../../core/widgets/shown_amounts.dart';
import '../../../core/formatting/dates.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/formatting/words.dart';

/// A credit card: the last statement and when it is due, with 繳卡款;
/// what has been spent since, the credit left, purchases paid in
/// instalments and the card's closing and payment days. Every sum comes
/// from [CardSummary]; the page only shows them and passes on the taps.
class CardPage extends StatelessWidget {
  const CardPage({
    super.key,
    required this.ledger,
    required this.nav,
    required this.accountId,
  });

  final Ledger ledger;
  final Nav nav;
  final String accountId;

  /// Lets the person move the next close by up to a week, as banks do
  /// around holidays.
  Future<void> _moveClose(BuildContext context, CardSummary card) async {
    final scheduled = card.scheduledClose;
    final picked = await pickDate(
      context,
      title: '這期改在哪天結帳',
      selected: card.nextClose,
      latest: scheduled.add(const Duration(days: 7)),
      marked: {scheduled},
    );
    if (picked == null) return;
    if (picked.difference(scheduled).inDays.abs() > 7) {
      if (context.mounted) showNote(context, '結帳日最多只能前後移動 7 天');
      return;
    }
    ledger.accountCommands.moveClose(card.card.id, scheduled, picked);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        // Gone by another way, such as a restore: nothing to show.
        if (!ledger.accounts.contains(accountId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) => nav.back());
          return const SizedBox.shrink();
        }
        final card = CardSummary.of(ledger, ledger.account(accountId));
        return HeadedList(
          padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s4),
          header: CenterHeader(
            card.card.name,
            onBack: nav.back,
            actions: [
              TextButton(
                onPressed: () async {
                  final gone = await editAccount(
                    context,
                    ledger,
                    account: card.card,
                  );
                  // Deleted or archived: back to the accounts.
                  if (gone) nav.back();
                },
                style: wordButton(Hue.accent),
                child: const Text(Words.edit),
              ),
            ],
          ),
          children: [
            _statement(card),
            _actions(context, card),
            _figures(card),
            Padding(
              padding: const EdgeInsets.only(top: Space.s2),
              child: FigureCard(
                color: Hue.card,
                icon: Glyph.calendar,
                label: '下次結帳',
                value: _day(card.nextClose),
                sub: '遇假日可以前後調整 7 天內',
                trailing: const GlyphIcon(Glyph.edit, size: 16),
                onTap: () => _moveClose(context, card),
              ),
            ),
            _extras(card),
            if (card.plans.isNotEmpty) ..._plans(card),
            ..._unbilled(card),
            const SectionTitle('設定'),
            _settings(card),
          ],
        );
      },
    );
  }

  /// The last statement, what is owed on it and 繳卡款.
  Widget _statement(CardSummary card) {
    final owed = card.owed;
    final left = card.daysLeft;
    final payment = card.payment;
    return HeroFigure(
      icon: Glyph.card,
      label: '本期帳單 · ${_day(card.start)}–${_day(card.end)}',
      trailing: Pill(owed == 0 ? '已繳清' : '已出帳'),
      value: ledger.money(owed),
      valueColor: owed > 0 ? Hue.negative : Hue.positive,
      sub: owed == 0
          ? '這期已繳清'
          : '繳款截止 ${_day(card.due)}（${left < 0 ? '已逾期' : '還有 $left 天'}）',
      child: payment == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: Space.s3),
              child: FilledButton(
                onPressed: () =>
                    nav.compose(type: EntryType.transfer, draft: payment),
                style: solidButton(
                  Hue.accent,
                  minimumSize: Size.fromHeight(44),
                  radius: Radii.medium,
                ),
                child: const Text('繳卡款'),
              ),
            ),
    );
  }

  /// The same actions as every account's page, under its figure.
  Widget _actions(BuildContext context, CardSummary card) => Padding(
    padding: const EdgeInsets.only(top: Space.s2),
    child: Row(
      children: [
        Expanded(
          child: AccountAction(
            icon: Glyph.add,
            label: '記一筆',
            onTap: () => nav.compose(draft: card.spending),
          ),
        ),
        // 對帳 needs NT$: another currency would need a rate.
        if (!card.card.foreign) ...[
          const SizedBox(width: Space.s2),
          Expanded(
            child: AccountAction(
              icon: Glyph.calculator,
              label: '對帳',
              onTap: () => reconcileAccount(context, ledger, card.card),
            ),
          ),
        ],
      ],
    ),
  );

  /// What has been spent since the close, and the credit left.
  Widget _figures(CardSummary card) {
    final limit = card.limit;
    final available = card.available;
    final used = card.usedShare;
    return CardRow([
      FigureCard(
        color: Hue.card,
        icon: Glyph.calendar,
        label: '本期未出帳',
        value: ledger.money(card.spentSince),
        sub: '第 ${card.daysGone} / ${card.cycleDays} 天',
        child: Padding(
          padding: const EdgeInsets.only(top: Space.s2),
          child: LinearProgressIndicator(
            value: card.cycleDays == 0 ? 0 : card.daysGone / card.cycleDays,
            minHeight: 6,
            borderRadius: BorderRadius.circular(Radii.extraSmall),
            color: Hue.accent,
            backgroundColor: Hue.accentTrack,
          ),
        ),
      ),
      FigureCard(
        color: Hue.card,
        icon: Glyph.budget,
        label: '可用額度',
        value: available == null ? '—' : ledger.money(available),
        sub: limit == null
            ? '未設定額度'
            : card.pending == 0
            ? '總額度 ${ledger.orDots(shortAmount(limit))}'
            : '含分期未繳 ${ledger.money(card.pending)}',
        // How much of the limit is taken, the instalments still to be
        // billed included.
        child: used == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: Space.s2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(
                      value: used,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(Radii.extraSmall),
                      color: card.nearLimit ? Hue.negative : Hue.accent,
                      backgroundColor: Hue.accentTrack,
                    ),
                    const SizedBox(height: Space.s1),
                    Text('已用 ${card.usedPercent}%', style: mutedSmall),
                  ],
                ),
              ),
      ),
    ]);
  }

  /// Cashback and fees this year, each with ＋ to record one.
  Widget _extras(CardSummary card) => CardRow([
    FigureCard(
      color: Hue.positive,
      icon: Glyph.sparkle,
      label: '今年回饋',
      value: ledger.money(card.taggedThisYear('回饋', EntryType.income)),
      valueColor: Hue.positive,
      sub: '本期 ${ledger.money(card.taggedSinceClose('回饋', EntryType.income))}',
      trailing: const GlyphIcon(Glyph.add, size: 16),
      onTap: () => nav.compose(
        type: EntryType.income,
        draft: card.extra(EntryType.income),
      ),
    ),
    FigureCard(
      color: Hue.negative,
      icon: Glyph.ticket,
      label: '今年年費',
      value: ledger.money(card.taggedThisYear('年費', EntryType.expense)),
      trailing: const GlyphIcon(Glyph.add, size: 16),
      onTap: () => nav.compose(
        type: EntryType.expense,
        draft: card.extra(EntryType.expense),
      ),
    ),
  ]);

  /// The purchases still being paid in instalments.
  List<Widget> _plans(CardSummary card) => [
    SectionTitle(
      '分期中',
      trailing: Text('${card.plans.length} 筆', style: mutedSmall),
    ),
    GroupBox(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s4,
        vertical: Space.s1,
      ),
      child: Column(
        children: [
          for (final e in card.plans)
            _plan(
              e,
              card.periodsBilled(e),
              card.periodAmount(e),
              card.unbilledOf(e),
            ),
        ],
      ),
    ),
  ];

  /// The entries since the close.
  List<Widget> _unbilled(CardSummary card) => [
    SectionTitle(
      '本期未出帳',
      trailing: Text(
        '${_day(card.end.add(const Duration(days: 1)))} 起',
        style: mutedSmall,
      ),
    ),
    if (card.unbilled.isEmpty)
      const Text('還沒有新的刷卡', style: TextStyle(color: Hue.muted))
    else
      GroupBox(
        // None: a row's 編輯 and 刪除 reach the card's edges.
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (final e in card.unbilled)
              EntryRow(
                ledger: ledger,
                entry: e,
                onOpen: nav.showEntry,
                divider: !identical(e, card.unbilled.last),
              ),
          ],
        ),
      ),
  ];

  /// The card's billing days and limit.
  Widget _settings(CardSummary card) {
    final limit = card.limit;
    return GroupBox(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s4,
        vertical: Space.s1,
      ),
      child: Column(
        children: [
          _setting('結帳日', '每月 ${card.closingDay} 日'),
          const Divider(height: 1),
          _setting('繳款日', '每月 ${card.dueDay} 日'),
          const Divider(height: 1),
          _setting('信用額度', limit == null ? '未設定' : ledger.money(limit)),
        ],
      ),
    );
  }

  static String _day(DateTime day) => formatMd(day);

  /// An instalment purchase: [periods] of its periods billed, the last
  /// of them [each], and [left] still to bill.
  Widget _plan(Entry e, int periods, int each, int left) {
    final category = ledger.category(e.category);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s2),
      child: Row(
        children: [
          RoundIcon(
            iconFor(category.icon),
            shownColor(Color(category.color)),
            size: 34,
          ),
          const SizedBox(width: Space.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.title,
                        style: const TextStyle(fontSize: TextSize.body),
                      ),
                    ),
                    Text(
                      '${ledger.money(each)} / 期',
                      style: const TextStyle(
                        fontSize: TextSize.body,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.s2),
                LinearProgressIndicator(
                  value: periods / e.installments,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(Radii.extraSmall),
                  color: shownColor(Color(category.color)),
                  backgroundColor: Hue.track,
                ),
                const SizedBox(height: Space.s1),
                Text(
                  '第 $periods / ${e.installments} 期 · '
                  '剩 ${ledger.money(left)}',
                  style: mutedSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _setting(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s3),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: TextSize.body)),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: TextSize.body,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
