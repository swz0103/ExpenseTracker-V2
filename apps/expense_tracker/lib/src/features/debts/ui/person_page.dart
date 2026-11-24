part of 'debts_page.dart';

/// The page of one person paid for: what they owe and for how long, 幫忙付
/// and 收回 (all that is owed, which can be changed), each sum still owed
/// with its days, and everything with them.
class PersonPage extends StatelessWidget {
  const PersonPage({
    super.key,
    required this.ledger,
    required this.nav,
    required this.personId,
  });

  final Ledger ledger;
  final Nav nav;
  final String personId;

  /// Opens the composer on money paid for [person] from the main account
  /// ([lend]), or on money paid back, all that is owed by default.
  void _move(Account person, {required bool lend}) {
    final main = ledger.accounts.main;
    final owed = ledger.balanceService.balance(person.id);
    nav.compose(
      type: EntryType.transfer,
      draft: Entry(
        id: '',
        date: ledger.today,
        type: EntryType.transfer,
        amount: lend || owed < 0 ? 0 : owed,
        account: lend ? main : person.id,
        category: transferCategory,
        to: lend ? person.id : main,
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

  Future<void> _delete(BuildContext context, Account person) async {
    final used = ledger.accountCommands.isUsed(person.id);
    final ok = await confirm(
      context,
      '刪除「${person.name}」？',
      Words.delete,
      danger: true,
      body: used ? '已記的紀錄會保留，這個人收起來不再出現。' : null,
    );
    if (!ok) return;
    if (used) {
      ledger.accountCommands.updateAccount(person.copyWith(archived: true));
    } else {
      ledger.accountCommands.removeAccount(person.id);
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
              _DebtHero(
                color: color,
                lead: _Initial(person.name, size: 60),
                label: balance < 0 ? '你欠${person.name}' : '還欠你',
                value: ledger.orDots(groupDigits(balance.abs())),
                lines: [
                  if (oldest == null)
                    '沒有待收回的'
                  else
                    '${countOf(owed.length, CountUnit.entries)}還沒收回 · 最久 ${countOf(_days(ledger, oldest), CountUnit.days)}',
                ],
                menu: DotsMenu([
                  DotsItem(Glyph.edit, '改名', () => _rename(context, person)),
                  DotsItem(
                    Glyph.trash,
                    Words.delete,
                    () => _delete(context, person),
                    danger: true,
                  ),
                ]),
              ),
              const SizedBox(height: Space.s3),
              _actions(person, balance, color),
            ]),
            if (owed.isNotEmpty)
              ..._boardRuns(
                '還沒收回',
                owed.length,
                (i) => _owedRow(owed[i].$1, owed[i].$2),
              ),
            ..._boardRuns(
              '往來紀錄',
              entries.length,
              (i) => _movementRow(entries[i], person.id, color, left),
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
          child: _Action(
            glyph: Glyph.add,
            label: '幫忙付',
            color: color,
            onTap: () => _move(person, lend: true),
          ),
        ),
        const SizedBox(width: Space.s3),
        Expanded(
          child: _Action(
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

  /// A sum paid for the person and not yet paid back: what it was for,
  /// its day, and how long it has waited.
  Widget _owedRow(Entry e, int left) {
    return QuoteRow(
      onTap: () => nav.showEntry(ledger.entryQueryService.groupLead(e)),
      title: _what(e),
      detail: switch (advanceStatus(amount: e.amount, left: left)) {
        AdvanceStatus.partlySettled =>
          '${formatMd(e.date)} · '
              '${advanceLook(AdvanceStatus.partlySettled).words} · '
              '共 ${ledger.orDots(groupDigits(e.amount))}',
        _ => formatMd(e.date),
      },
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DaysTag(_days(ledger, e.date)),
          const SizedBox(width: Space.s3),
          RowFigure(ledger.orDots(groupDigits(left))),
        ],
      ),
    );
  }

  /// One movement with the person: paid back in green with a minus, paid
  /// for with a ＋.
  Widget _movementRow(
    Entry e,
    String person,
    Color color,
    Map<String, int> stillOwed,
  ) {
    final back = e.account == person;
    // A sum paid for them says where it stands: 未收回, 部分收回 or
    // 已結清, as the advance rules decide.
    final status = back
        ? null
        : advanceLook(
            advanceStatus(amount: e.amount, left: stillOwed[e.id] ?? 0),
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
            ? '−${ledger.orDots(groupDigits(e.amount))}'
            : ledger.orDots(groupDigits(e.amount)),
        spoken: ledger.spoken(
          back ? -e.amount : e.amount,
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
  });

  final Ledger ledger;
  final Nav nav;
  final String loanId;

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
              _DebtHero(
                color: color,
                lead: share == null
                    ? SquareIcon(Glyph.loan, color, size: 60)
                    : _PaidRing(share: share, color: color, size: 96),
                label: '尚欠',
                value: ledger.orDots(groupDigits(owed)),
                lines: _lines(loan, owed),
                menu: DotsMenu([
                  DotsItem(Glyph.edit, Words.edit, () async {
                    final gone = await editLoan(context, ledger, loan: loan);
                    if (gone) nav.back();
                  }),
                  DotsItem(
                    Glyph.check,
                    '對帳',
                    () => reconcileAccount(context, ledger, loan),
                  ),
                ]),
              ),
              const SizedBox(height: Space.s3),
              _payButton(loan, color),
            ]),
            ..._boardRuns(
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
    return _Action(
      glyph: Glyph.add,
      label: '記一筆還款',
      color: color,
      solid: true,
      onTap: () => nav.compose(
        type: EntryType.transfer,
        draft: Entry(
          id: '',
          date: ledger.today,
          type: EntryType.transfer,
          amount: 0,
          account: ledger.accounts.main,
          category: transferCategory,
          to: loan.id,
        ),
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
