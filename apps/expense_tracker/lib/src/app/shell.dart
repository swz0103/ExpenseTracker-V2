import 'package:flutter/material.dart';

import '../features/entries/compose/composer.dart';
import '../core/look/glyphs.dart';
import '../core/look/haptics.dart';
import '../core/look/theme.dart';
import '../core/look/widgets.dart';
import '../core/ledger/ledger.dart';
import '../core/problems.dart';
import '../core/quick_action.dart';
import '../features/settings/model/services.dart';
import '../features/accounts/ui/account_page.dart';
import '../features/accounts/ui/accounts.dart';
import '../features/budgets/ui/budgets.dart';
import '../features/cards/ui/card_page.dart';
import '../features/categories/ui/categories_page.dart';
import '../features/investments/ui/holding_page.dart';
import '../features/investments/ui/investments.dart';
import '../features/categories/ui/labels_page.dart';
import '../features/entries/ui/ledger_page.dart';
import '../features/more/ui/more.dart';
import '../core/nav.dart';
import '../features/overview/ui/overview.dart';
import '../features/recurring/ui/recurring_page.dart';
import '../features/reports/ui/reports.dart';
import '../features/settings/ui/settings_page.dart';

enum _Tab { overview, ledger, accounts, more }

/// The app frame: the page, and 總覽、紀錄、記一筆、帳戶、更多 along the
/// bottom. Pages under 更多 and each account open in
/// place with a back arrow; the system back closes them first.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.ledger,
    this.services = const Services(),
  });

  final Ledger ledger;

  /// Keys, backups, the calendar and screen hiding; none in the preview.
  final Services services;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _tab = _Tab.overview;
  Place? _page;
  late final Nav _nav = Nav(
    open: _open,
    back: () => setState(() => _page = _parent),
    compose: _compose,
    showEntry: (entry) => _compose(entry: entry),
    market: widget.services.market,
  );

  @override
  void initState() {
    super.initState();
    widget.ledger.problem.addListener(_report);
    widget.services.quick?.addListener(_quickAction);
    // An action the app was opened with waits for the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _quickAction());
  }

  @override
  void dispose() {
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
  Place? get _parent => _page?.parent;

  /// Opens [page] over the current tab, which back returns to.
  void _open(Place page) => setState(() => _page = page);

  Future<void> _compose({
    EntryType type = EntryType.expense,
    Entry? entry,
    Entry? draft,
    Entry? refundOf,
  }) async {
    final ledger = widget.ledger;
    final result = await openComposer(
      context,
      ledger,
      type: type,
      entry: entry,
      draft: draft,
      refundOf: refundOf,
      photos: widget.services.receipts,
    );
    if (result == null || !mounted) return;
    final (outcome, saved) = result;
    if (outcome == ComposeOutcome.refund) {
      await _compose(refundOf: saved);
      return;
    }
    if (outcome == ComposeOutcome.deleted) {
      Haptics.medium();
      final removed = ledger.remove(saved.id);
      if (removed == null) return;
      showNote(
        context,
        '已刪除「${saved.title}」',
        action: '復原',
        onAction: () => ledger.restore(removed),
      );
      return;
    }
    Haptics.light();
    // A new expense or income offers 再記一筆: the same again, on today,
    // to change what differs; anything else, to look at what was saved.
    final again =
        entry == null &&
        (saved.type == EntryType.expense || saved.type == EntryType.income) &&
        !saved.isRefund;
    showNote(
      context,
      entry == null ? '已記下' : '已更新',
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

  Widget _body() {
    final ledger = widget.ledger;
    final page = _page;
    if (page != null) {
      return switch (page) {
        // Gone, such as after a restore: back to the tab.
        AccountPlace(:final id) when !ledger.hasAccount(id) => _gone(),
        AccountPlace(:final id) =>
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
        SettingsPlace(:final part) => SettingsPage(
          key: ValueKey(page),
          ledger: ledger,
          nav: _nav,
          services: widget.services,
          part: part,
        ),
        HoldingPlace(:final code) => HoldingPage(
          key: ValueKey(page),
          ledger: ledger,
          nav: _nav,
          code: code,
        ),
        SectionPlace(:final section) => switch (section) {
          Section.reports => ReportsPage(ledger: ledger, nav: _nav),
          Section.investments => InvestmentsPage(ledger: ledger, nav: _nav),
          Section.budgets => BudgetsPage(ledger: ledger, nav: _nav),
          Section.recurring => RecurringPage(ledger: ledger, nav: _nav),
          Section.categories => CategoriesPage(ledger: ledger, nav: _nav),
          Section.labels => LabelsPage(ledger: ledger, nav: _nav),
          Section.settings => SettingsPage(
            ledger: ledger,
            nav: _nav,
            services: widget.services,
          ),
        },
      };
    }
    return switch (_tab) {
      _Tab.overview => OverviewPage(
        ledger: ledger,
        nav: _nav,
        preferences: widget.services.preferences,
      ),
      _Tab.ledger => LedgerPage(ledger: ledger, nav: _nav),
      _Tab.accounts => AccountsPage(ledger: ledger, nav: _nav),
      _Tab.more => MorePage(ledger: ledger, nav: _nav),
    };
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _page == null && _tab == _Tab.overview,
      onPopInvokedWithResult: (popped, _) {
        if (popped) return;
        setState(() {
          if (_page != null) {
            _page = _parent;
          } else {
            _tab = _Tab.overview;
          }
        });
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
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
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.tab,
    required this.onTab,
    required this.onRecord,
  });

  final _Tab tab;
  final ValueChanged<_Tab> onTab;
  final VoidCallback onRecord;

  static const _items = [
    (_Tab.overview, Glyph.overview, '總覽'),
    (_Tab.ledger, Glyph.records, '紀錄'),
    (_Tab.accounts, Glyph.wallet, '帳戶'),
    (_Tab.more, Glyph.other, '更多'),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Hue.panel,
        border: Border(top: rowRule),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              for (final (i, (item, icon, label)) in _items.indexed) ...[
                if (i == 2)
                  Expanded(
                    child: Center(
                      child: Tooltip(
                        message: '記一筆',
                        child: Pressable(
                          depth: 0.9,
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Hue.accentGlow,
                                  blurRadius: 12,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Hue.accent,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () {
                                  Haptics.light();
                                  onRecord();
                                },
                                child: const SizedBox(
                                  width: 50,
                                  height: 50,
                                  child: Center(
                                    child: GlyphIcon(
                                      Glyph.add,
                                      color: Hue.onAccent,
                                      weight: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: InkResponse(
                    onTap: () => onTab(item),
                    highlightColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedScale(
                          scale: item == tab ? 1.12 : 1,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutBack,
                          child: GlyphIcon(
                            icon,
                            color: item == tab ? Hue.accent : Hue.muted,
                            tinted: item == tab,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            color: item == tab ? Hue.accent : Hue.muted,
                            fontWeight: item == tab
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
