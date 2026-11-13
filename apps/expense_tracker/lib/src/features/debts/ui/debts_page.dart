import 'package:flutter/material.dart';

import '../../../core/look/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/nav.dart';
import '../../../core/look/dialogs.dart';
import '../../accounts/compose/account_editor.dart';
import '../../accounts/ui/reconcile_sheet.dart';

/// The people paid for, most owed first, open ones only.
List<Account> peopleOwing(Ledger ledger) => [
  for (final a in ledger.openAccounts)
    if (a.kind == AccountKind.receivable) a,
]..sort((a, b) => ledger.balance(b.id).compareTo(ledger.balance(a.id)));

/// The open loans.
List<Account> openLoans(Ledger ledger) => [
  for (final a in ledger.openAccounts)
    if (a.kind == AccountKind.loan) a,
];

/// What [person] owes in all, as a positive amount or nothing.
int owedFrom(Ledger ledger, Account person) {
  final balance = ledger.balance(person.id);
  return balance > 0 ? balance : 0;
}

/// What is left on [loan], as a positive amount or nothing.
int owedOn(Ledger ledger, Account loan) {
  final balance = ledger.balance(loan.id);
  return balance < 0 ? -balance : 0;
}

/// How much of [loan] is paid, 0 to 1; null without its amount when taken
/// out.
double? paidShare(Ledger ledger, Account loan) {
  final principal = loan.principal;
  if (principal == null || principal <= 0) return null;
  final share = (principal - owedOn(ledger, loan)) / principal;
  return share < 0 ? 0.0 : (share > 1 ? 1.0 : share);
}

/// Whole days since [day].
int _days(Ledger ledger, DateTime day) {
  final days = ledger.today.difference(day).inDays;
  return days < 0 ? 0 : days;
}

/// The first letter of a name, for its circle.
String _initial(String name) {
  final runes = name.trim().runes;
  return runes.isEmpty ? '?' : String.fromCharCode(runes.first);
}

/// 代墊與借貸: money paid for people and loans, kept apart from 我的帳戶
/// as investments are. On top, both ways apart (別人欠你 | 你還欠: a small
/// sum lent and a mortgage do not add up to anything); then a square for
/// each person, and a card for each loan with how much is paid as a ring.
class DebtsPage extends StatelessWidget {
  const DebtsPage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final people = peopleOwing(ledger);
        final loans = openLoans(ledger);
        final lent = people.fold<int>(0, (sum, a) => sum + owedFrom(ledger, a));
        final borrowed = loans.fold<int>(
          0,
          (sum, a) => sum + owedOn(ledger, a),
        );
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            CenterHeader(
              '代墊與借貸',
              onBack: nav.back,
              actions: [
                HeaderButton(
                  glyph: Glyph.add,
                  label: '新增貸款',
                  onTap: () => editLoan(context, ledger),
                ),
              ],
            ),
            _BothWays(
              ledger: ledger,
              lent: lent,
              people: people.where((p) => owedFrom(ledger, p) > 0).length,
              borrowed: borrowed,
              loans: loans.length,
            ),
            const RuleHead('代墊'),
            if (people.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text(
                  '記一筆支出時按「代墊」選人，幫忙付的錢就會記在這裡，收回時在收入選「對方還錢」。',
                  style: mutedSmall,
                ),
              )
            else
              CardGrid(columns: 3, gap: 10, [
                for (final person in people)
                  _PersonSquare(
                    ledger: ledger,
                    person: person,
                    onTap: () => nav.open(Pages.debt(person.id)),
                  ),
              ]),
            const RuleHead('貸款'),
            if (loans.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text('房貸、信貸或車貸，按右上的＋新增。', style: mutedSmall),
              ),
            for (final loan in loans)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _LoanCard(
                  ledger: ledger,
                  loan: loan,
                  onTap: () => nav.open(Pages.debt(loan.id)),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 別人欠你 | 你還欠 on the page's main card, a thin rule between.
class _BothWays extends StatelessWidget {
  const _BothWays({
    required this.ledger,
    required this.lent,
    required this.people,
    required this.borrowed,
    required this.loans,
  });

  final Ledger ledger;
  final int lent;
  final int people;
  final int borrowed;
  final int loans;

  @override
  Widget build(BuildContext context) {
    Widget half(String label, String value, String sub, Color color) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Hue.muted,
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
        Text(sub, style: mutedSmall),
      ],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Hue.hero, Hue.tile],
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: half(
                '別人欠你',
                ledger.orDots(groupDigits(lent)),
                '$people 人',
                lent > 0 ? Hue.positive : Hue.ink,
              ),
            ),
            const VerticalDivider(width: 32, color: Hue.accentRule),
            Expanded(
              child: half(
                '你還欠',
                ledger.orDots(shortAmount(borrowed)),
                '$loans 筆貸款',
                Hue.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The first letter of a name in a solid circle of its colour.
class _Initial extends StatelessWidget {
  const _Initial(this.name, {this.size = 46});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: nameColor(name), shape: BoxShape.circle),
    alignment: Alignment.center,
    child: Text(
      _initial(name),
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        fontSize: size * 0.42,
        fontWeight: FontWeight.w800,
        color: const Color(0xFFFFFFFF),
      ),
    ),
  );
}

/// A person paid for: their initial, name, what they owe and how long
/// the oldest of it has waited, on their colour's tint.
class _PersonSquare extends StatelessWidget {
  const _PersonSquare({
    required this.ledger,
    required this.person,
    required this.onTap,
  });

  final Ledger ledger;
  final Account person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final owed = ledger.owedBy(person.id);
    final oldest = owed.isEmpty ? null : owed.last.$1.date;
    final color = nameColor(person.name);
    final ink = deepOf(color);
    return ColorCard(
      color: color,
      radius: 20,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
      child: Column(
        children: [
          _Initial(person.name),
          const SizedBox(height: 8),
          Text(
            person.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              ledger.orDots(groupDigits(owedFrom(ledger, person))),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            oldest == null ? '沒有欠款' : '最久 ${_days(ledger, oldest)} 天',
            maxLines: 1,
            style: TextStyle(fontSize: 12, color: ink),
          ),
        ],
      ),
    );
  }
}

/// How much of a loan is paid, as a ring with the share in the middle.
class _PaidRing extends StatelessWidget {
  const _PaidRing({required this.share, required this.color, this.size = 64});

  final double share;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      fit: StackFit.expand,
      children: [
        CircularProgressIndicator(
          value: share,
          strokeWidth: size / 9,
          strokeCap: StrokeCap.round,
          color: color,
          backgroundColor: tintOf(color, 0.3),
        ),
        Center(
          child: Text(
            '${(share * 100).round()}%',
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: size / 4,
              fontWeight: FontWeight.w800,
              color: deepOf(color),
            ),
          ),
        ),
      ],
    ),
  );
}

/// A loan: how much is paid as a ring, its name and amount taken out,
/// and what is left, on its colour's tint.
class _LoanCard extends StatelessWidget {
  const _LoanCard({
    required this.ledger,
    required this.loan,
    required this.onTap,
  });

  final Ledger ledger;
  final Account loan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final share = paidShare(ledger, loan);
    final principal = loan.principal;
    final color = nameColor(loan.name);
    final ink = deepOf(color);
    return ColorCard(
      color: color,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 14, 18, 14),
      child: Row(
        children: [
          if (share != null)
            _PaidRing(share: share, color: color)
          else
            SquareIcon(Glyph.loan, color, size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loan.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
                if (principal != null)
                  Text(
                    '原借 ${ledger.orDots(groupDigits(principal))}',
                    style: TextStyle(fontSize: 13, color: ink),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('尚欠', style: TextStyle(fontSize: 12, color: ink)),
              Text(
                ledger.orDots(groupDigits(owedOn(ledger, loan))),
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A big card in [color]: [lead] on the left, then a small label, the
/// figure and a line, with the ⋯ menu in the corner.
class _DebtHero extends StatelessWidget {
  const _DebtHero({
    required this.color,
    required this.lead,
    required this.label,
    required this.value,
    required this.lines,
    required this.menu,
  });

  final Color color;
  final Widget lead;
  final String label;
  final String value;
  final List<String> lines;
  final Widget menu;

  @override
  Widget build(BuildContext context) {
    final ink = deepOf(color);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 12, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tintOf(color, 0.4), tintOf(color, 0.2)],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          lead,
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                for (final line in lines)
                  Text(
                    line,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
              ],
            ),
          ),
          menu,
        ],
      ),
    );
  }
}

/// A wide button with an icon: tinted, or solid in [color] when [solid].
class _Action extends StatelessWidget {
  const _Action({
    required this.glyph,
    required this.label,
    required this.color,
    required this.onTap,
    this.solid = false,
  });

  final Glyph glyph;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final ink = solid ? const Color(0xFFFFFFFF) : deepOf(color);
    return Material(
      color: solid ? color : tintOf(color, 0.2),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GlyphIcon(glyph, size: 18, color: ink, tinted: false),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small heading over a white board, or a line when it is empty.
List<Widget> _board(
  String title,
  List<Widget> rows, {
  String empty = '還沒有紀錄',
}) => [
  RuleHead(title),
  if (rows.isEmpty)
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(empty, style: mutedSmall),
    )
  else
    QuoteBoard(rows),
];

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
    final main = ledger.mainAccount;
    final owed = ledger.balance(person.id);
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
    final lead = ledger.groupLead(e);
    if (!identical(lead, e) && lead.type == EntryType.expense) {
      return lead.merchant.isNotEmpty ? lead.merchant : lead.category;
    }
    return '代墊';
  }

  Future<void> _rename(BuildContext context, Account person) async {
    final name = await askText(context, '改名', initial: person.name);
    if (name == null || name == person.name) return;
    ledger.updateAccount(person.copyWith(name: name));
  }

  Future<void> _delete(BuildContext context, Account person) async {
    final used = ledger.isUsed(person.id);
    final ok = await confirm(
      context,
      '刪除「${person.name}」？',
      '刪除',
      danger: true,
      body: used ? '已記的紀錄會保留，這個人收起來不再出現。' : null,
    );
    if (!ok) return;
    if (used) {
      ledger.updateAccount(person.copyWith(archived: true));
    } else {
      ledger.removeAccount(person.id);
    }
    nav.back();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        if (!ledger.hasAccount(personId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) => nav.back());
          return const SizedBox.shrink();
        }
        final person = ledger.account(personId);
        final balance = ledger.balance(person.id);
        final owed = ledger.owedBy(person.id);
        final entries = [
          for (final e in ledger.entries)
            if (e.account == person.id || e.to == person.id) e,
        ]..sort((a, b) => b.date.compareTo(a.date));
        final color = nameColor(person.name);
        final oldest = owed.isEmpty ? null : owed.last.$1.date;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            CenterHeader(person.name, onBack: nav.back),
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
                  '刪除',
                  () => _delete(context, person),
                  danger: true,
                ),
              ]),
            ),
            const SizedBox(height: 12),
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
                const SizedBox(width: 12),
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
                    onTap: () => nav.showEntry(ledger.groupLead(e)),
                    title: _what(e),
                    detail:
                        '${e.date.month}/${e.date.day}'
                        '${left < e.amount ? ' · 共 ${ledger.orDots(groupDigits(e.amount))}' : ''}',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _DaysTag(_days(ledger, e.date)),
                        const SizedBox(width: 12),
                        RowFigure(ledger.orDots(groupDigits(left))),
                      ],
                    ),
                  ),
              ]),
            ..._board('往來紀錄', [
              for (final e in entries) _move2(e, person.id, color),
            ]),
          ],
        );
      },
    );
  }

  /// One movement with the person: paid back in green with a minus, paid
  /// for with a ＋.
  Widget _move2(Entry e, String person, Color color) {
    final back = e.account == person;
    return QuoteRow(
      onTap: () => nav.showEntry(ledger.groupLead(e)),
      lead: SquareIcon(
        back ? Glyph.check : Glyph.add,
        back ? Hue.positive : color,
        size: 40,
      ),
      title: back ? '收回' : _what(e),
      detail: '${e.date.month}/${e.date.day}',
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: long ? const Shade(0xFFC9A34A, 0xFFDDBE73) : Hue.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$days 天',
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: 12,
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
        if (!ledger.hasAccount(loanId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) => nav.back());
          return const SizedBox.shrink();
        }
        final loan = ledger.account(loanId);
        final owed = owedOn(ledger, loan);
        final share = paidShare(ledger, loan);
        final principal = loan.principal;
        final color = nameColor(loan.name);
        final entries = [
          for (final e in ledger.entries)
            if (e.account == loan.id || e.to == loan.id) e,
        ]..sort((a, b) => b.date.compareTo(a.date));
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            CenterHeader(loan.name, onBack: nav.back),
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
              ],
              menu: DotsMenu([
                DotsItem(Glyph.edit, '編輯', () async {
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
            const SizedBox(height: 12),
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
                  account: ledger.mainAccount,
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
                      ? '還款 ${e.date.month}/${e.date.day}'
                      : '${e.title} ${e.date.month}/${e.date.day}',
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
