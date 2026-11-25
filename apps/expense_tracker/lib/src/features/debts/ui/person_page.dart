import 'package:flutter/material.dart';

import '../../../../design_system/display/amount.dart';
import '../../../../design_system/display/status.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/navigation/nav.dart';
import '../../../core/design_system/dialogs.dart';

import 'package:ledger_loans/calc/loan_plan.dart';

import '../../../core/widgets/icons.dart';
import '../../../core/widgets/shown_amounts.dart';
import '../../../../design_system/display/date.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/formatting/words.dart';
import '../model/debts.dart';
import '../../../core/messages/done_messages.dart';
import '../../../core/messages/flow_messages.dart';
import '../../../core/messages/trash_messages.dart';
import '../../../core/messages/validation_messages.dart';
import 'debts_page.dart';
import 'debts_loan_card.dart';

/// The page of one person paid for: what they owe and for how long, 幫忙付
/// and 收回 (all that is owed, which can be changed), each sum still owed
/// with its days, and everything with them.
class PersonPage extends StatelessWidget {
  const PersonPage({
    super.key,
    required this.ledger,
    required this.nav,
    required this.personId,
    required this.settle,
  });

  final Ledger ledger;
  final Nav nav;
  final String personId;

  /// Settles what is left with the person and archives them, as the
  /// account form does; true when archived. Given by the app.
  final Future<bool> Function(BuildContext context, Account person, int left)
  settle;

  /// Opens the composer on money paid for [person] from the main account
  /// ([lend]), or on money paid back, all that is owed by default.
  void _move(Account person, {required bool lend}) {
    final drafts = ledger.transferDrafts;
    nav.compose(
      type: EntryType.transfer,
      draft: lend
          ? drafts.lend(person.id)
          : drafts.payBack(
              person.id,
              owed: ledger.balanceService.balance(person.id),
            ),
    );
  }

  /// What a sum paid for someone was for: its note, else the spending
  /// it was part of.
  String _what(Entry e) {
    if (e.note.isNotEmpty) return e.note;
    final lead = ledger.entryQueryService.groupLead(e);
    if (!identical(lead, e) && lead.type == EntryType.expense) {
      return lead.merchant.isNotEmpty ? lead.merchant : lead.category;
    }
    return Words.lend;
  }

  Future<void> _rename(BuildContext context, Account person) async {
    final name = await askText(context, '改名', initial: person.name);
    if (name == null || name == person.name) return;
    ledger.accountCommands.updateAccount(person.copyWith(name: name));
  }

  /// Deletes [person]: one with dealings kept is archived instead, so
  /// what was written stays. Either is told with 復原 and not asked first
  /// (D82), unless deleted entries in the trash still name them: those go
  /// for good with them, which cannot be undone, so it is asked (D78).
  /// One who still owes money, or is owed it, once what is dated ahead
  /// has come, is not archived as they are (DEB-01): asked whether to
  /// settle first, as the account form does ([settle], review
  /// 35); kept, the page stays.
  Future<void> _delete(BuildContext context, Account person) async {
    if (ledger.accountCommands.usedOutsideTrash(person.id)) {
      final left = ledger.balanceService.finalBalance(person.id);
      if (left != 0) {
        final settle = await confirm(
          context,
          validationMessage(const ArchivedOwing()),
          Words.settleArchive,
          body: SettleWords.owingBody(person.name),
          cancel: SettleWords.keep,
        );
        if (!settle || !context.mounted) return;
      }
      if (await settle(context, person, left)) {
        nav.back();
      }
      return;
    }
    final trashed = ledger.accountCommands.trashedNaming(person.id);
    if (trashed.isNotEmpty) {
      final ok = await confirm(
        context,
        '刪除「${person.name}」？',
        Words.delete,
        danger: true,
        body: trashedNamingNote(trashed.length),
      );
      if (!ok || !context.mounted) return;
      ledger.entryCommands.discardTrashed(trashed);
    }
    final undo = ledger.accountCommands.removeAccount(person.id);
    if (undo != null) {
      if (trashed.isEmpty) {
        showUndo(context, DoneWords.deleted(person.name), undo);
      } else {
        showNote(context, DoneWords.deleted(person.name));
      }
    }
    nav.back();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // The person's balance and dealings, their categories' icons.
      listenable: ledger.watch(const {
        Topic.entries,
        Topic.accounts,
        Topic.categories,
      }),
      builder: (context, _) {
        if (!ledger.accounts.contains(personId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) => nav.back());
          return const SizedBox.shrink();
        }
        final person = ledger.account(personId);
        final balance = ledger.balanceService.balance(person.id);
        final owed = ledger.reportService.owedBy(person.id);
        final entries = ledger.balanceService.entriesOf(person.id);
        final color = nameColor(person.name);
        final oldest = owed.isEmpty ? null : owed.last.$1.date;
        final left = {for (final (lent, left) in owed) lent.id: left};
        // Rows built as they come on screen: a person's dealings can be
        // as many as the book holds.
        return HeadedList.lazy(
          padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s8),
          header: CenterHeader(person.name, onBack: nav.back),
          runs: [
            LineRun.each([
              DebtHero(
                color: color,
                lead: PersonInitial(person.name, size: 60),
                label: balance < 0 ? '你欠${person.name}' : '還欠你',
                // In the person's own currency (review 41).
                value: ledger.moneyIn(balance.abs(), person.currency),
                lines: [
                  if (oldest == null)
                    '沒有待收回的'
                  else
                    '${countOf(owed.length, CountUnit.entries)}還沒收回 · 最久 ${countOf(daysSince(ledger.today, oldest), CountUnit.days)}',
                ],
                menu: DotsMenu([
                  DotsItem(Glyph.edit, '改名', () => _rename(context, person)),
                  DotsItem(
                    Glyph.trash,
                    // One with dealings is archived (封存), not deleted.
                    entries.isEmpty ? Words.delete : Words.archive,
                    () => _delete(context, person),
                    danger: true,
                  ),
                ]),
              ),
              const SizedBox(height: Space.s3),
              _actions(person, balance, color),
            ]),
            if (owed.isNotEmpty)
              ...debtBoardRuns(
                '還沒收回',
                owed.length,
                (i) => _owedRow(owed[i].$1, owed[i].$2, person),
              ),
            ...debtBoardRuns(
              '往來紀錄',
              entries.length,
              (i) => _movementRow(entries[i], person, color, left),
            ),
          ],
        );
      },
    );
  }

  /// 幫忙付 and 收回, side by side; 收回 only while they owe.
  Widget _actions(Account person, int balance, Color color) {
    return Row(
      children: [
        Expanded(
          child: DebtAction(
            glyph: Glyph.add,
            label: '幫忙付',
            color: color,
            onTap: () => _move(person, lend: true),
          ),
        ),
        const SizedBox(width: Space.s3),
        Expanded(
          child: DebtAction(
            glyph: Glyph.check,
            label: '收回',
            color: color,
            solid: true,
            onTap: balance > 0 ? () => _move(person, lend: false) : null,
          ),
        ),
      ],
    );
  }

  /// What [e] put on [person]'s account, in the person's currency: for a
  /// sum paid over from another currency, what arrived (review 41), the
  /// scale what is left of it is in.
  int _lent(Entry e, Account person) =>
      ledger.balanceService.effect(e, person.id);

  /// A sum paid for the person and not yet paid back: what it was for,
  /// its day, and how long it has waited, in the person's currency.
  Widget _owedRow(Entry e, int left, Account person) {
    final lent = _lent(e, person);
    return QuoteRow(
      onTap: () => nav.showEntry(ledger.entryQueryService.groupLead(e)),
      title: _what(e),
      detail: switch (advanceStatus(amount: lent, left: left)) {
        AdvanceStatus.partlySettled =>
          '${formatMd(e.date)} · '
              '${advanceLook(AdvanceStatus.partlySettled).words} · '
              '共 ${ledger.moneyIn(lent, person.currency)}',
        _ => formatMd(e.date),
      },
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DaysTag(daysSince(ledger.today, e.date)),
          const SizedBox(width: Space.s3),
          RowFigure(ledger.moneyIn(left, person.currency)),
        ],
      ),
    );
  }

  /// One movement with the person: paid back in green with a minus, paid
  /// for with a ＋; each in the currency of the account it was paid from
  /// (review 41: a sum paid in NT\$ for a person kept in US\$ says NT\$).
  Widget _movementRow(
    Entry e,
    Account person,
    Color color,
    Map<String, int> stillOwed,
  ) {
    final back = e.account == person.id;
    final currency = ledger.account(e.account).currency;
    // A sum paid for them says where it stands: 未收回, 部分收回 or
    // 已結清, as the advance rules decide, in the person's currency.
    final status = back
        ? null
        : advanceLook(
            advanceStatus(amount: _lent(e, person), left: stillOwed[e.id] ?? 0),
          );
    return QuoteRow(
      onTap: () => nav.showEntry(ledger.entryQueryService.groupLead(e)),
      lead: SquareIcon(
        back ? Glyph.check : Glyph.add,
        back ? AppColors.positive : color,
        size: 40,
      ),
      title: back ? '收回' : _what(e),
      detail: status == null
          ? formatMd(e.date)
          : '${formatMd(e.date)} · ${status.words}',
      trailing: RowFigure(
        back
            ? '−${ledger.moneyIn(e.amount, currency)}'
            : ledger.moneyIn(e.amount, currency),
        spoken: ledger.spoken(
          back ? -e.amount : e.amount,
          currency: currency,
          sense: AmountSense.plain,
        ),
        color: back ? AppColors.positive : AppColors.ink,
      ),
    );
  }
}

/// How many days a sum has waited: gold after two weeks.
class _DaysTag extends StatelessWidget {
  const _DaysTag(this.days);

  final int days;

  @override
  Widget build(BuildContext context) {
    final long = days > 14;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s2,
        vertical: Space.s1,
      ),
      decoration: BoxDecoration(
        color: long ? Palette.gold : AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.small),
      ),
      child: Text(
        countOf(days, CountUnit.days),
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: TextSize.caption,
          fontWeight: FontWeight.w800,
          color: long ? AppColors.onAccent : AppColors.muted,
        ),
      ),
    );
  }
}

/// The page of one loan: how much is paid as a big ring, what is left,
/// what was taken out and paid; ⋯ with 編輯 and 對帳; 記一筆還款; and
/// every payment with the account it came from.
class LoanPage extends StatelessWidget {
  const LoanPage({
    super.key,
    required this.ledger,
    required this.nav,
    required this.loanId,
    required this.edit,
    required this.reconcile,
  });

  final Ledger ledger;
  final Nav nav;
  final String loanId;

  /// Opens the loan's form from 編輯; true when it was deleted or
  /// archived there. The accounts' form, given by the app.
  final Future<bool> Function(BuildContext context, Account loan) edit;

  /// Opens 對帳 for the loan: the accounts' sheet, given by the app.
  final Future<void> Function(BuildContext context, Account loan) reconcile;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // The loan's terms, balance and payments.
      listenable: ledger.watch(const {Topic.entries, Topic.accounts}),
      builder: (context, _) {
        if (!ledger.accounts.contains(loanId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) => nav.back());
          return const SizedBox.shrink();
        }
        final loan = ledger.account(loanId);
        final owed = owedOn(ledger.balanceService, loan);
        final share = paidShare(ledger.balanceService, loan);
        final color = nameColor(loan.name);
        final entries = ledger.balanceService.entriesOf(loan.id);
        // Rows built as they come on screen, however many payments.
        return HeadedList.lazy(
          padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s8),
          header: CenterHeader(loan.name, onBack: nav.back),
          runs: [
            LineRun.each([
              DebtHero(
                color: color,
                lead: share == null
                    ? SquareIcon(Glyph.loan, color, size: 60)
                    : PaidRing(share: share, color: color, size: 96),
                label: '尚欠',
                value: ledger.orDots(groupDigits(owed)),
                lines: _lines(loan, owed),
                menu: DotsMenu([
                  DotsItem(Glyph.edit, Words.edit, () async {
                    final gone = await edit(context, loan);
                    if (gone) nav.back();
                  }),
                  DotsItem(Glyph.check, '對帳', () => reconcile(context, loan)),
                ]),
              ),
              const SizedBox(height: Space.s3),
              _payButton(loan, color),
            ]),
            ...debtBoardRuns(
              '還款紀錄',
              entries.length,
              (i) => _paymentRow(entries[i], loan, color),
            ),
          ],
        );
      },
    );
  }

  /// The lines under what is owed: what was borrowed and paid, and the
  /// month's payment when the loan's terms give one.
  List<String> _lines(Account loan, int owed) {
    final principal = loan.principal;
    return [
      if (principal != null) ...[
        '原借 ${ledger.orDots(groupDigits(principal))}',
        '已還 ${ledger.orDots(groupDigits(principal - owed < 0 ? 0 : principal - owed))}',
      ],
      if (loanPlan(
            amount: principal,
            rate: loan.loan?.rate,
            months: loan.loan?.months,
            repay: loan.loan?.repay ?? LoanRepay.even,
          )
          case final plan?)
        '${repayName(loan.loan?.repay ?? LoanRepay.even)} · 每月約 '
            '${ledger.orDots(groupDigits(plan.first))}',
    ];
  }

  /// 記一筆還款: opens the composer on a payment into [loan].
  Widget _payButton(Account loan, Color color) {
    return DebtAction(
      glyph: Glyph.add,
      label: '記一筆還款',
      color: color,
      solid: true,
      onTap: () => nav.compose(
        type: EntryType.transfer,
        draft: ledger.transferDrafts.payInto(loan.id),
      ),
    );
  }

  /// A payment into the loan with the account it came from, or the money
  /// taken out.
  Widget _paymentRow(Entry e, Account loan, Color color) {
    return QuoteRow(
      onTap: () => nav.showEntry(e),
      lead: SquareIcon(
        e.to == loan.id ? Glyph.check : Glyph.loan,
        color,
        size: 40,
      ),
      title: e.to == loan.id
          ? '還款 ${formatMd(e.date)}'
          : '${e.title} ${formatMd(e.date)}',
      detail: e.to == loan.id ? '從 ${ledger.account(e.account).name}' : null,
      trailing: RowFigure(ledger.orDots(groupDigits(e.amount))),
    );
  }
}
