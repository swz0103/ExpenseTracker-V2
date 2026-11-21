import 'package:flutter/material.dart';

import '../../../core/formatting/figures.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/navigation/nav.dart';
import '../../../core/design_system/dialogs.dart';
import '../../accounts/forms/account_editor.dart';
import '../../accounts/forms/reconcile_sheet.dart';

import 'package:domain/loans.dart';

import '../../../core/widgets/icons.dart';
import '../../../core/widgets/shown_amounts.dart';
import '../../../core/formatting/dates.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/formatting/words.dart';
import '../model/debts.dart';

part 'person_page.dart';
part 'debts_loan_card.dart';

/// The people paid for, most owed first, open ones only.
List<Account> peopleOwing(Ledger ledger) =>
    [
      for (final a in ledger.accounts.open)
        if (a.kind == AccountKind.receivable) a,
    ]..sort(
      (a, b) => ledger.balanceService
          .balance(b.id)
          .compareTo(ledger.balanceService.balance(a.id)),
    );

/// The open loans.
List<Account> openLoans(Ledger ledger) => [
  for (final a in ledger.accounts.open)
    if (a.kind == AccountKind.loan) a,
];

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
        final balances = ledger.balanceService;
        final lent = people.fold(0, (sum, a) => sum + owedFrom(balances, a));
        final borrowed = loans.fold(0, (sum, a) => sum + owedOn(balances, a));
        return HeadedList(
          padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s8),
          header: CenterHeader(
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
          children: [
            _BothWays(
              ledger: ledger,
              lent: lent,
              people: people.where((p) => owedFrom(balances, p) > 0).length,
              borrowed: borrowed,
              loans: loans.length,
            ),
            const RuleHead(Words.lend),
            if (people.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: Space.s1,
                  vertical: Space.s2,
                ),
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
                    onTap: () => nav.open(AppRoutes.debt(person.id)),
                  ),
              ]),
            const RuleHead('貸款'),
            if (loans.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: Space.s1,
                  vertical: Space.s2,
                ),
                child: Text('房貸、信貸或車貸，按右上的＋新增。', style: mutedSmall),
              ),
            for (final loan in loans)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.s2),
                child: _LoanCard(
                  ledger: ledger,
                  loan: loan,
                  onTap: () => nav.open(AppRoutes.debt(loan.id)),
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
            fontSize: TextSize.small,
            fontWeight: FontWeight.w700,
            color: AppColors.muted,
          ),
        ),
        // Both figures in full on a line of the same height, so the two
        // halves stay level even when one shrinks to fit.
        SizedBox(
          height: TextSize.figure * 1.4,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: TextSize.figure,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ),
        Text(sub, style: mutedSmall),
      ],
    );
    return HeroCard(
      padding: const EdgeInsets.fromLTRB(
        Space.s5,
        Space.s4,
        Space.s5,
        Space.s4,
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: half(
                '別人欠你',
                ledger.orDots(groupDigits(lent)),
                '$people 人',
                lent > 0 ? AppColors.positive : AppColors.ink,
              ),
            ),
            const VerticalDivider(width: 32, color: AppColors.accentRule),
            Expanded(
              child: half(
                '你還欠',
                ledger.orDots(groupDigits(borrowed)),
                '$loans 筆貸款',
                AppColors.ink,
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
        color: AppColors.onSolid,
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
    final owed = ledger.reportService.owedBy(person.id);
    final oldest = owed.isEmpty ? null : owed.last.$1.date;
    final color = nameColor(person.name);
    final ink = deepOf(color);
    final amount = ledger.orDots(
      groupDigits(owedFrom(ledger.balanceService, person)),
    );
    final age = oldest == null ? '沒有欠款' : '最久 ${_days(ledger, oldest)} 天';
    return ColorCard(
      color: color,
      radius: Radii.largeIncreased,
      onTap: onTap,
      // Read from the name on, not the initial on the round mark.
      label: '${person.name}，欠你 $amount，$age',
      padding: const EdgeInsets.fromLTRB(
        Space.s2,
        Space.s4,
        Space.s2,
        Space.s3,
      ),
      child: Column(
        children: [
          _Initial(person.name),
          const SizedBox(height: Space.s2),
          Text(
            person.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: TextSize.body,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              amount,
              style: const TextStyle(
                fontSize: TextSize.heading,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            age,
            maxLines: 1,
            style: TextStyle(fontSize: TextSize.caption, color: ink),
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
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s4,
        Space.s3,
        Space.s4,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.extraLarge),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tintOf(color, 0.4), tintOf(color, 0.2)],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final words = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: TextSize.small,
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
                    fontSize: TextSize.big,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              for (final line in lines)
                OneLine(
                  line,
                  style: TextStyle(
                    fontSize: TextSize.small,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
            ],
          );
          // Large text on a narrow phone: the words go under the mark,
          // where the figure has the whole width.
          final grow = textGrowth(context);
          if (box.maxWidth / grow < 230) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [lead, const Spacer(), menu],
                ),
                const SizedBox(height: Space.s2),
                words,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              lead,
              const SizedBox(width: Space.s4),
              Expanded(child: words),
              menu,
            ],
          );
        },
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
    final ink = solid ? chosenInk(color) : deepOf(color);
    return Material(
      color: solid ? chosenFill(color) : tintOf(color, 0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.large),
        side: solid ? chosenEdge(color) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.large),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GlyphIcon(glyph, size: 18, color: ink, tinted: false),
              const SizedBox(width: Space.s2),
              Text(
                label,
                style: TextStyle(
                  fontSize: TextSize.title,
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
      padding: const EdgeInsets.symmetric(horizontal: Space.s1),
      child: Text(empty, style: mutedSmall),
    )
  else
    QuoteBoard(rows),
];
