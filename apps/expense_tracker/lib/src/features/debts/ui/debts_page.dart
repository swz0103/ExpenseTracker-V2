import 'package:flutter/material.dart';

import '../../../core/look/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/nav.dart';
import '../../../core/ui/entry_tile.dart';
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

/// Days since [day], as a page says them.
String _since(Ledger ledger, DateTime day) {
  final days = ledger.today.difference(day).inDays;
  return days <= 0 ? '今天' : '$days 天前';
}

/// The first letter of a name, for its circle.
String _initial(String name) {
  final runes = name.trim().runes;
  return runes.isEmpty ? '?' : String.fromCharCode(runes.first);
}

/// 代墊與借貸: money paid for people and loans, kept apart from 我的帳戶
/// as investments are. What is owed both ways on top, then a card for
/// each person to slide through, and one for each loan.
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
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            PageHeader(
              '代墊與借貸',
              onBack: nav.back,
              trailing: TextButton.icon(
                onPressed: () => editLoan(context, ledger),
                icon: const GlyphIcon(Glyph.add, size: 16),
                label: const Text('貸款'),
                style: TextButton.styleFrom(foregroundColor: Hue.accent),
              ),
            ),
            Tile(
              hero: true,
              icon: Glyph.transfer,
              label: '往來淨額',
              value: ledger.moneySigned(lent - borrowed),
              sub: '別人欠你減掉你欠的貸款',
              child: TileStats([
                (Glyph.income, '別人欠你', ledger.money(lent), Hue.ink),
                (Glyph.payout, '貸款尚欠', ledger.money(borrowed), Hue.ink),
              ]),
            ),
            SectionHead(
              '代墊',
              trailing: Text('${people.length} 人', style: mutedSmall),
            ),
            if (people.isEmpty)
              const Text('還沒有代墊。記一筆時選「代墊」，就會出現在這裡。', style: mutedSmall)
            else
              SizedBox(
                // Taller with larger text, so the words still fit.
                height:
                    140 +
                    50 *
                        (MediaQuery.textScalerOf(context).scale(16) / 16 - 1)
                            .clamp(0.0, 2.0)
                            .toDouble(),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: people.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => _PersonCard(
                    ledger: ledger,
                    person: people[i],
                    onTap: () => nav.open(Pages.debt(people[i].id)),
                  ),
                ),
              ),
            SectionHead(
              '貸款',
              trailing: Text('${loans.length} 筆', style: mutedSmall),
            ),
            if (loans.isEmpty)
              const Text('還沒有貸款。按右上的「貸款」新增。', style: mutedSmall),
            for (final loan in loans)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
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

/// A person paid for: their initial, name, what they owe and how long
/// the oldest of it has waited.
class _PersonCard extends StatelessWidget {
  const _PersonCard({
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
    return SizedBox(
      width: 120,
      child: SoftPanel(
        color: Hue.white,
        padding: const EdgeInsets.all(12),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBadge.letter(
              _initial(person.name),
              Hue.receivable,
              size: 36,
            ),
            const Spacer(),
            Text(
              person.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                ledger.money(owedFrom(ledger, person)),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              oldest == null ? '沒有欠款' : '最久 ${_since(ledger, oldest)}',
              maxLines: 1,
              style: const TextStyle(fontSize: 11.5, color: Hue.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// A loan: how much is paid as a ring, its name and amount taken out,
/// and what is left.
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
    return SoftPanel(
      color: Hue.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      onTap: onTap,
      child: Row(
        children: [
          if (share != null) ...[
            RingGauge(share: share, size: 56),
            const SizedBox(width: 14),
          ] else ...[
            IconBadge(Glyph.loan, Hue.investment, size: 40),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loan.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (principal != null)
                  Text('原借 ${ledger.money(principal)}', style: mutedSmall),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('尚欠', style: TextStyle(fontSize: 12, color: Hue.muted)),
              Text(
                ledger.money(owedOn(ledger, loan)),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The page of one person paid for: what they owe, each sum still owed
/// and how long it has waited, and everything with them.
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
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 20, 32),
          children: [
            PageHeader(
              person.name,
              onBack: nav.back,
              trailing: TextButton(
                onPressed: () async {
                  final gone = await editAccount(
                    context,
                    ledger,
                    account: person,
                  );
                  if (gone) nav.back();
                },
                style: TextButton.styleFrom(foregroundColor: Hue.accent),
                child: const Text('編輯'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Tile(
                    hero: true,
                    icon: kindIcon(AccountKind.receivable),
                    label: balance < 0 ? '你欠${person.name}' : '還欠你',
                    value: ledger.money(balance.abs()),
                    sub: owed.isEmpty ? '沒有待收回的' : '${owed.length} 筆還沒收回',
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _move(person, lend: true),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Hue.accent,
                              minimumSize: const Size.fromHeight(46),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('幫忙付'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: balance > 0
                                ? () => _move(person, lend: false)
                                : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: Hue.accent,
                              minimumSize: const Size.fromHeight(46),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(balance > 0 ? '收回全部' : '收回'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (owed.isNotEmpty) ...[
                    SectionHead(
                      '還沒收回',
                      trailing: Text(
                        ledger.money(
                          owed.fold<int>(0, (sum, o) => sum + o.$2),
                        ),
                        style: mutedSmall,
                      ),
                    ),
                    SoftPanel(
                      color: Hue.white,
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (final (i, (e, left)) in owed.indexed)
                            InkWell(
                              onTap: () => nav.showEntry(ledger.groupLead(e)),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 11,
                                ),
                                decoration: BoxDecoration(
                                  border: i == owed.length - 1
                                      ? null
                                      : const Border(
                                          bottom: BorderSide(color: Hue.line),
                                        ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _what(e),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            '${e.date.month}/${e.date.day} · '
                                            '${_since(ledger, e.date)}',
                                            style: mutedSmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          ledger.money(left),
                                          style: const TextStyle(
                                            fontSize: 15.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (left < e.amount)
                                          Text(
                                            '共 ${ledger.money(e.amount)}',
                                            style: mutedSmall,
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SectionHead('紀錄'),
                  if (entries.isEmpty)
                    const Text('還沒有紀錄', style: TextStyle(color: Hue.muted))
                  else
                    SoftPanel(
                      color: Hue.white,
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (final e in entries)
                            EntryRow(
                              ledger: ledger,
                              entry: e,
                              onOpen: nav.showEntry,
                              divider: !identical(e, entries.last),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The page of one loan: what is left, how much is paid, a payment to
/// record, and every payment.
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
        final entries = [
          for (final e in ledger.entries)
            if (e.account == loan.id || e.to == loan.id) e,
        ]..sort((a, b) => b.date.compareTo(a.date));
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 20, 32),
          children: [
            PageHeader(
              loan.name,
              onBack: nav.back,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => reconcileAccount(context, ledger, loan),
                    style: TextButton.styleFrom(foregroundColor: Hue.accent),
                    child: const Text('對帳'),
                  ),
                  TextButton(
                    onPressed: () async {
                      final gone = await editLoan(context, ledger, loan: loan);
                      if (gone) nav.back();
                    },
                    style: TextButton.styleFrom(foregroundColor: Hue.accent),
                    child: const Text('編輯'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Tile(
                    hero: true,
                    icon: Glyph.loan,
                    label: '尚欠',
                    value: ledger.money(owed),
                    sub: principal == null || share == null
                        ? null
                        : '原借 ${ledger.money(principal)} · '
                              '已還 ${(share * 100).round()}%',
                    child: share == null
                        ? null
                        : Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: share,
                                minHeight: 6,
                                color: Hue.accent,
                                backgroundColor: Hue.accentTrack,
                              ),
                            ),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: FilledButton(
                      onPressed: () => nav.compose(
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
                      style: FilledButton.styleFrom(
                        backgroundColor: Hue.accent,
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('記一筆還款'),
                    ),
                  ),
                  const SectionHead('還款紀錄'),
                  if (entries.isEmpty)
                    const Text('還沒有紀錄', style: TextStyle(color: Hue.muted))
                  else
                    SoftPanel(
                      color: Hue.white,
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (final e in entries)
                            EntryRow(
                              ledger: ledger,
                              entry: e,
                              onOpen: nav.showEntry,
                              divider: !identical(e, entries.last),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
