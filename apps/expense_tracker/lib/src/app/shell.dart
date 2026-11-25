import 'dart:async';

import 'package:flutter/material.dart';

import '../features/entries/forms/composer.dart';
import '../../design_system/display/amount.dart';
import '../core/design_system/glyphs.dart';
import '../core/design_system/haptics.dart';
import '../core/design_system/theme.dart';
import '../core/design_system/design_system.dart';
import '../core/ledger/ledger.dart';
import '../core/ledger/trading.dart' show defaultBrokerDiscount;
import '../core/widgets/entry_tile.dart' show deleteEntries;
import '../core/widgets/problem_note.dart';
import '../core/platform/quick_action.dart';
import '../core/widgets/tour.dart';
import '../features/settings/model/platform_services.dart';
import '../features/accounts/forms/account_editor.dart'
    show editLoan, settleAndArchive;
import '../features/accounts/forms/reconcile_sheet.dart';
import '../features/accounts/ui/account_page.dart';
import '../features/accounts/ui/accounts.dart';
import '../features/budgets/ui/budgets.dart';
import '../features/accounts/ui/card_page.dart';
import '../features/categories/ui/categories_page.dart';
import '../features/debts/ui/debts_page.dart';
import '../features/debts/ui/person_page.dart';
import '../features/investments/ui/holding_page.dart';
import '../features/investments/ui/investments.dart';
import '../features/tags/ui/tags_page.dart';
import '../features/entries/ui/entries_page.dart';
import 'more_page.dart';
import '../core/navigation/nav.dart';
import '../features/overview/ui/overview.dart';
import '../features/recurring/ui/recurring_page.dart';
import '../features/reports/ui/reports.dart';
import 'settings_page.dart';
import '../core/widgets/shown_amounts.dart';
import '../core/design_system/spacing.dart';
import '../core/design_system/motion.dart';
import '../core/formatting/words.dart';
import 'between_frames.dart';

enum _Tab { overview, ledger, accounts, more }

/// The app frame: the page, and 總覽、紀錄、記一筆、帳戶、更多 along the
/// bottom. Pages under 更多 and each account open in
/// place with a back arrow; the system back closes them first.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.ledger,
    this.services = const PlatformServices(),
    this.tour = false,
  });

  final Ledger ledger;

  /// Walks through 記一筆, the month's figures and 更多 first: for a
  /// ledger just started.
  final bool tour;

  /// Keys, backups, the calendar and screen hiding; none in the preview.
  final PlatformServices services;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _tab = _Tab.overview;

  /// The page over the tabs. A ledger reopened after a restore was given
  /// up starts on the page the person left from.
  late AppRoute? _page = widget.services.takeReturn?.call();
  late var _touring = widget.tour;

  /// The places the tour lights.
  final _recordKey = GlobalKey();
  final _summaryKey = GlobalKey();
  final _moreKey = GlobalKey();

  void _toured() {
    setState(() => _touring = false);
    widget.services.preferences?.update(started: true);
  }

  Widget _tour() => Tour(
    onDone: _toured,
    stops: [
      TourStop(
        target: _recordKey,
        round: true,
        pad: 10,
        glyph: Glyph.add,
        title: '記一筆從這裡開始',
        detail: '支出、收入、轉帳都從這顆記',
      ),
      TourStop(
        target: _summaryKey,
        pad: 6,
        glyph: Glyph.eye,
        title: '這個月的收支都在這',
        detail: '點眼睛可以先把金額藏起來',
      ),
      TourStop(
        target: _moreKey,
        round: true,
        pad: 8,
        glyph: Glyph.safe,
        title: '帳本每天自動備份',
        detail: '照片要另外開雲端硬碟備份',
      ),
    ],
  );
  late final Nav _nav = Nav(
    open: _open,
    back: () => setState(() => _page = _parent),
    compose: _compose,
    showEntry: (entry) => _compose(entry: entry),
    market: widget.services.market,
    saveFile: widget.services.backupManager?.exportBytes,
  );

  @override
  void initState() {
    super.initState();
    widget.ledger.problem.addListener(_report);
    widget.services.quick?.addListener(_quickAction);
    // An action the app was opened with waits for the first frame; so
    // does answering every stock's holdings, a step between frames, which
    // the first sale save would otherwise pay for (PERF-3).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _quickAction();
      unawaited(widget.ledger.entryValidator.prepare(_betweenFrames.next));
    });
  }

  final _betweenFrames = BetweenFrames();

  @override
  void dispose() {
    _betweenFrames.stop();
    widget.services.quick?.removeListener(_quickAction);
    widget.ledger.problem.removeListener(_report);
    super.dispose();
  }

  /// Opens the composer a shortcut, the widget or a notification asked
  /// for, once.
  void _quickAction() {
    final quick = widget.services.quick;
    final asked = quick?.value;
    if (quick == null || asked == null || !mounted) return;
    quick.value = null;
    Navigator.of(context).popUntil((route) => route.isFirst);
    _compose(
      type: asked == QuickAction.income ? EntryType.income : EntryType.expense,
    ).ignore();
  }

  /// Says why the ledger refused a change; the screens already show what
  /// was kept instead.
  void _report() {
    final problem = widget.ledger.problem;
    final error = problem.value;
    if (error == null || !mounted) return;
    problem.value = null;
    showProblem(context, error);
  }

  /// Where back leads from the open page: a holding returns to 投資.
  AppRoute? get _parent => _page?.parent;

  /// Opens [page] over the current tab, which back returns to.
  void _open(AppRoute page) => setState(() => _page = page);

  Future<void> _compose({
    EntryType type = EntryType.expense,
    Entry? entry,
    Entry? draft,
    Entry? refundOf,
  }) async {
    final ledger = widget.ledger;
    // What each holding had realized, so a sale can say what it made.
    final realizedBefore = {
      for (final h in ledger.holdings.all) h.code: h.realized,
    };
    final result = await openComposer(
      context,
      ledger,
      type: type,
      entry: entry,
      draft: draft,
      refundOf: refundOf,
      photos: widget.services.receipts,
      scan: widget.services.scanQr,
      brokerDiscount:
          widget.services.preferences?.brokerDiscount ?? defaultBrokerDiscount,
    );
    if (result == null || !mounted) return;
    final (outcome, saved) = result;
    if (outcome == ComposeOutcome.refund) {
      await _compose(refundOf: saved);
      return;
    }
    if (outcome == ComposeOutcome.deleted) {
      deleteEntries(context, ledger, [saved]);
      return;
    }
    // A firmer knock when this put a budget over its allowance.
    if (ledger.budgetService.overAfter(saved)) {
      Haptics.medium();
    } else {
      Haptics.light();
    }
    // A new expense or income offers 再記一筆: the same again, on today,
    // to change what differs; anything else, to look at what was saved.
    final again =
        entry == null &&
        (saved.type == EntryType.expense || saved.type == EntryType.income) &&
        !saved.isRefund;
    final sold = saved.type == EntryType.sell ? saved.holding : null;
    final made = sold == null
        ? null
        : (ledger.holdings.all
                      .where((h) => h.code == sold)
                      .firstOrNull
                      ?.realized ??
                  0) -
              (realizedBefore[sold] ?? 0);
    final note =
        '${entry == null ? '已記下' : '已更新'}'
        '${made == null || made == 0 ? '' : ' · 已實現 ${ledger.orDots(signed(made))}'}';
    showNote(
      context,
      note,
      spoken: made == null ? null : ledger.readAloud(note, made),
      action: again ? '再記一筆' : '查看',
      onAction: again
          ? () => _compose(type: saved.type, draft: _again(saved))
          : () => _compose(entry: saved),
    );
  }

  /// A new entry like [saved]: its category, account, merchant, amount and
  /// tags, on today, without its note, receipt or instalments.
  Entry _again(Entry saved) => Entry(
    id: '',
    date: widget.ledger.today,
    type: saved.type,
    amount: saved.amount,
    account: saved.account,
    category: saved.category,
    merchant: saved.merchant,
    tags: saved.tags,
    parts: saved.parts,
    home: saved.home,
  );

  /// A page whose account is gone closes after this frame.
  Widget _gone() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nav.back();
    });
    return const SizedBox.shrink();
  }

  /// A page under 更多.
  Widget _morePage(Ledger ledger, MoreDestination page) => switch (page) {
    MoreDestination.reports => ReportsPage(ledger: ledger, nav: _nav),
    MoreDestination.investments => InvestmentsPage(ledger: ledger, nav: _nav),
    MoreDestination.debts => DebtsPage(ledger: ledger, nav: _nav),
    MoreDestination.budgets => BudgetsPage(ledger: ledger, nav: _nav),
    MoreDestination.recurring => RecurringPage(ledger: ledger, nav: _nav),
    MoreDestination.categories => CategoriesPage(ledger: ledger, nav: _nav),
    MoreDestination.tags => TagsPage(ledger: ledger, nav: _nav),
    MoreDestination.settings => SettingsPage(
      ledger: ledger,
      nav: _nav,
      services: widget.services,
    ),
  };

  Widget _body() {
    final page = _page;
    if (page != null) return _routed(widget.ledger, page);
    return switch (_tab) {
      _Tab.overview => OverviewPage(
        ledger: widget.ledger,
        nav: _nav,
        preferences: widget.services.preferences,
        summaryKey: _touring ? _summaryKey : null,
      ),
      _Tab.ledger => EntriesPage(ledger: widget.ledger, nav: _nav),
      _Tab.accounts => AccountsPage(ledger: widget.ledger, nav: _nav),
      _Tab.more => MorePage(ledger: widget.ledger, nav: _nav),
    };
  }

  /// The page [page] opens over the tabs.
  Widget _routed(Ledger ledger, AppRoute page) => switch (page) {
    // Gone, such as after a restore: back to the tab.
    AccountRoute(:final id) ||
    DebtRoute(:final id) when !ledger.accounts.contains(id) => _gone(),
    // Money paid for someone and loans have pages of their own,
    // wherever they are opened from.
    AccountRoute(:final id) || DebtRoute(:final id)
        when ledger.account(id).kind == AccountKind.receivable =>
      PersonPage(
        key: ValueKey(page),
        ledger: ledger,
        nav: _nav,
        personId: id,
        settle: (context, person, left) =>
            settleAndArchive(context, ledger, person, left: left),
      ),
    AccountRoute(:final id) || DebtRoute(:final id)
        when ledger.account(id).kind == AccountKind.loan =>
      LoanPage(
        key: ValueKey(page),
        ledger: ledger,
        nav: _nav,
        loanId: id,
        edit: (context, loan) => editLoan(context, ledger, loan: loan),
        reconcile: (context, loan) => reconcileAccount(context, ledger, loan),
      ),
    DebtRoute() => _gone(),
    AccountRoute(:final id) =>
      ledger.account(id).kind == AccountKind.card
          ? CardPage(
              key: ValueKey(page),
              ledger: ledger,
              nav: _nav,
              accountId: id,
            )
          : AccountPage(
              key: ValueKey(page),
              ledger: ledger,
              nav: _nav,
              accountId: id,
            ),
    TagRoute(:final name, :final merchant) => TagPage(
      key: ValueKey(page),
      ledger: ledger,
      nav: _nav,
      name: name,
      merchant: merchant,
    ),
    SettingsRoute(:final part, :final sought) => SettingsPage(
      key: ValueKey(page),
      ledger: ledger,
      nav: _nav,
      services: widget.services,
      part: part,
      sought: sought,
    ),
    HoldingRoute(:final code) => HoldingPage(
      key: ValueKey(page),
      ledger: ledger,
      nav: _nav,
      code: code,
    ),
    RecurringRoute(:final view) => RecurringViewPage(
      key: ValueKey(page),
      ledger: ledger,
      nav: _nav,
      view: view,
    ),
    MerchantsRoute() => TagsPage(ledger: ledger, nav: _nav, merchants: true),
    SectionRoute(:final section) => _morePage(ledger, section),
  };

  @override
  Widget build(BuildContext context) {
    widget.services.onPlace?.call(_page);
    // Back on the first screen (總覽, no page open) leaves the app as the
    // home button does, on a phone: it stays open behind, so coming back
    // within the auto-lock time needs no unlocking. Where the app cannot
    // be put behind, back closes it.
    final first = _page == null && _tab == _Tab.overview;
    final leave = widget.services.leave;
    return PopScope(
      canPop: first && leave == null,
      onPopInvokedWithResult: (popped, _) {
        if (popped) return;
        if (first) {
          leave?.call().ignore();
          return;
        }
        setState(() {
          if (_page != null) {
            _page = _parent;
          } else {
            _tab = _Tab.overview;
          }
        });
      },
      child: Stack(
        children: [
          Positioned.fill(child: _frame()),
          if (_touring) Positioned.fill(child: _tour()),
        ],
      ),
    );
  }

  Widget _frame() {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AnimatedSwitcher(
          duration: Motion.of(context, Motion.medium1),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          // Only the page coming in is drawn: the one going out fading
          // under it leaves its words as a ghost.
          layoutBuilder: (current, previous) => current ?? const SizedBox(),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.03),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: KeyedSubtree(key: ValueKey((_tab, _page)), child: _body()),
        ),
      ),
      bottomNavigationBar: _BottomBar(
        tab: _tab,
        onTab: (tab) {
          if (tab != _tab || _page != null) Haptics.selection();
          setState(() {
            _tab = tab;
            _page = null;
          });
        },
        onRecord: () => _compose(),
        recordKey: _recordKey,
        moreKey: _moreKey,
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.tab,
    required this.onTab,
    required this.onRecord,
    this.recordKey,
    this.moreKey,
  });

  final _Tab tab;
  final ValueChanged<_Tab> onTab;
  final VoidCallback onRecord;

  /// The 記一筆 button and the 更多 tab, for the tour to find.
  final GlobalKey? recordKey;
  final GlobalKey? moreKey;

  static const _items = [
    (_Tab.overview, Glyph.overview, '總覽'),
    (_Tab.ledger, Glyph.records, '紀錄'),
    (_Tab.accounts, Glyph.wallet, Words.account),
    (_Tab.more, Glyph.other, '更多'),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(top: rowRule),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              for (final (i, (item, icon, label)) in _items.indexed) ...[
                if (i == 2) Expanded(child: Center(child: _record())),
                Expanded(child: _tabButton(context, item, icon, label)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 記一筆: the round accent button in the middle of the bar.
  Widget _record() => Tooltip(
    message: '記一筆',
    child: Pressable(
      depth: 0.9,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.accentGlow,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: AppColors.accent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              Haptics.light();
              onRecord();
            },
            child: SizedBox(
              key: recordKey,
              width: 50,
              height: 50,
              child: const Center(
                child: GlyphIcon(
                  Glyph.add,
                  color: AppColors.onAccent,
                  weight: 2,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  /// The tab for [item], a tap going to it.
  Widget _tabButton(
    BuildContext context,
    _Tab item,
    Glyph icon,
    String label,
  ) => InkResponse(
    key: Keys.tab(label),
    onTap: () => onTab(item),
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    child: Center(
      child: KeyedSubtree(
        key: item == _Tab.more ? moreKey : null,
        child: _tabMark(context, icon, label, chosen: item == tab),
      ),
    ),
  );

  /// A tab's icon over its name, the chosen one larger and in the accent.
  Widget _tabMark(
    BuildContext context,
    Glyph icon,
    String label, {
    required bool chosen,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      AnimatedScale(
        scale: chosen ? 1.12 : 1,
        duration: Motion.of(context, Motion.short4),
        curve: Curves.easeOutBack,
        child: GlyphIcon(
          icon,
          color: chosen ? AppColors.accent : AppColors.muted,
          tinted: chosen,
        ),
      ),
      const SizedBox(height: Space.half),
      Text(
        label,
        style: TextStyle(
          fontSize: TextSize.caption,
          color: chosen ? AppColors.accent : AppColors.muted,
          fontWeight: chosen ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    ],
  );
}
