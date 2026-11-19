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
      listenable: ledger,
      builder: (context, _) {
        if (!ledger.accounts.contains(personId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) => nav.back());
          return const SizedBox.shrink();
        }
        final person = ledger.account(personId);
        final balance = ledger.balanceService.balance(person.id);
        final owed = ledger.reportService.owedBy(person.id);
        final entries = [
          for (final e in ledger.entries.all)
            if (e.account == person.id || e.to == person.id) e,
        ]..sort((a, b) => b.date.compareTo(a.date));
        final color = nameColor(person.name);
        final oldest = owed.isEmpty ? null : owed.last.$1.date;
        return HeadedList(
          padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s8),
          header: CenterHeader(person.name, onBack: nav.back),
          children: [
            _DebtHero(
              color: color,
              lead: _Initial(person.name, size: 60),
              label: balance < 0 ? '你欠${person.name}' : '還欠你',
              value: ledger.orDots(groupDigits(balance.abs())),
              lines: [
                if (oldest == null)
                  '沒有待收回的'
                else
                  '${owed.length} 筆還沒收回 · 最久 ${_days(ledger, oldest)} 天',
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
            Row(
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
                    onTap: balance > 0
                        ? () => _move(person, lend: false)
                        : null,
                  ),
                ),
              ],
            ),
            if (owed.isNotEmpty)
              ..._board('還沒收回', [
                for (final (e, left) in owed)
                  QuoteRow(
                    onTap: () =>
                        nav.showEntry(ledger.entryQueryService.groupLead(e)),
                    title: _what(e),
                    detail:
                        '${formatMd(e.date)}'
                        '${left < e.amount ? ' · 共 ${ledger.orDots(groupDigits(e.amount))}' : ''}',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _DaysTag(_days(ledger, e.date)),
                        const SizedBox(width: Space.s3),
                        RowFigure(ledger.orDots(groupDigits(left))),
                      ],
                    ),
                  ),
              ]),
            ..._board('往來紀錄', [
              for (final e in entries) _movementRow(e, person.id, color),
            ]),
          ],
        );
      },
    );
  }

  /// One movement with the person: paid back in green with a minus, paid
  /// for with a ＋.
  Widget _movementRow(Entry e, String person, Color color) {
    final back = e.account == person;
    return QuoteRow(
      onTap: () => nav.showEntry(ledger.entryQueryService.groupLead(e)),
      lead: SquareIcon(
        back ? Glyph.check : Glyph.add,
        back ? Hue.positive : color,
        size: 40,
      ),
      title: back ? '收回' : _what(e),
      detail: formatMd(e.date),
      trailing: RowFigure(
        back
            ? '−${ledger.orDots(groupDigits(e.amount))}'
            : ledger.orDots(groupDigits(e.amount)),
        color: back ? Hue.positive : Hue.ink,
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
        color: long ? Palette.gold : Hue.surface,
        borderRadius: BorderRadius.circular(Radii.small),
      ),
      child: Text(
        '$days 天',
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: TextSize.caption,
          fontWeight: FontWeight.w800,
          color: long ? Hue.onAccent : Hue.muted,
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
      listenable: ledger,
      builder: (context, _) {
        if (!ledger.accounts.contains(loanId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) => nav.back());
          return const SizedBox.shrink();
        }
        final loan = ledger.account(loanId);
        final owed = owedOn(ledger, loan);
        final share = paidShare(ledger, loan);
        final principal = loan.principal;
        final color = nameColor(loan.name);
        final entries = [
          for (final e in ledger.entries.all)
            if (e.account == loan.id || e.to == loan.id) e,
        ]..sort((a, b) => b.date.compareTo(a.date));
        return HeadedList(
          padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s8),
          header: CenterHeader(loan.name, onBack: nav.back),
          children: [
            _DebtHero(
              color: color,
              lead: share == null
                  ? SquareIcon(Glyph.loan, color, size: 60)
                  : _PaidRing(share: share, color: color, size: 96),
              label: '尚欠',
              value: ledger.orDots(groupDigits(owed)),
              lines: [
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
              ],
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
            _Action(
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
            ),
            ..._board('還款紀錄', [
              for (final e in entries)
                QuoteRow(
                  onTap: () => nav.showEntry(e),
                  lead: SquareIcon(
                    e.to == loan.id ? Glyph.check : Glyph.loan,
                    color,
                    size: 40,
                  ),
                  title: e.to == loan.id
                      ? '還款 ${formatMd(e.date)}'
                      : '${e.title} ${formatMd(e.date)}',
                  detail: e.to == loan.id
                      ? '從 ${ledger.account(e.account).name}'
                      : null,
                  trailing: RowFigure(ledger.orDots(groupDigits(e.amount))),
                ),
            ]),
          ],
        );
      },
    );
  }
}
