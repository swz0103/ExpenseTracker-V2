import 'package:flutter/material.dart';

import '../compose/composer.dart';
import '../demo/ledger.dart';
import '../look/glyphs.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import 'account_page.dart';
import 'accounts.dart';
import 'budgets.dart';
import 'categories_page.dart';
import 'investments.dart';
import 'ledger_page.dart';
import 'more.dart';
import 'nav.dart';
import 'overview.dart';
import 'recurring_page.dart';
import 'reports.dart';
import 'settings_page.dart';

enum _Tab { overview, ledger, accounts, more }

/// The app frame: the page, and 總覽、紀錄、記一筆、帳戶、更多 along the
/// bottom. Pages under 更多 and each account open in
/// place with a back arrow; the system back closes them first.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.ledger});

  final Ledger ledger;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _tab = _Tab.overview;
  String? _page;
  late final Nav _nav = Nav(
    open: _open,
    back: () => setState(() => _page = null),
    compose: _compose,
    showEntry: (entry) => _compose(entry: entry),
  );

  void _open(String page) {
    setState(() {
      _page = page;
      _tab = page.startsWith('account:') ? _Tab.accounts : _Tab.more;
    });
  }

  Future<void> _compose({
    EntryType type = EntryType.expense,
    Entry? entry,
  }) async {
    final ledger = widget.ledger;
    final result = await openComposer(
      context,
      ledger,
      type: type,
      entry: entry,
    );
    if (result == null || !mounted) return;
    final (outcome, saved) = result;
    if (outcome == ComposeOutcome.deleted) {
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
    showNote(
      context,
      entry == null ? '已記下' : '已更新',
      action: '查看',
      onAction: () => _compose(entry: saved),
    );
  }

  Widget _body() {
    final ledger = widget.ledger;
    final page = _page;
    if (page != null) {
      if (page.startsWith('account:')) {
        return AccountPage(
          key: ValueKey(page),
          ledger: ledger,
          nav: _nav,
          accountId: page.substring('account:'.length),
        );
      }
      return switch (page) {
        Pages.reports => ReportsPage(ledger: ledger, nav: _nav),
        Pages.investments => InvestmentsPage(ledger: ledger, nav: _nav),
        Pages.budgets => BudgetsPage(ledger: ledger, nav: _nav),
        Pages.recurring => RecurringPage(ledger: ledger, nav: _nav),
        Pages.categories => CategoriesPage(ledger: ledger, nav: _nav),
        _ => SettingsPage(ledger: ledger, nav: _nav),
      };
    }
    return switch (_tab) {
      _Tab.overview => OverviewPage(ledger: ledger, nav: _nav),
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
            _page = null;
          } else {
            _tab = _Tab.overview;
          }
        });
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: KeyedSubtree(key: ValueKey((_tab, _page)), child: _body()),
          ),
        ),
        bottomNavigationBar: _BottomBar(
          tab: _tab,
          onTab: (tab) => setState(() {
            _tab = tab;
            _page = null;
          }),
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
        border: Border(top: BorderSide(color: Hue.line)),
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
                        child: Material(
                          color: Hue.positive,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: onRecord,
                            child: const SizedBox(
                              width: 44,
                              height: 44,
                              child: Center(
                                child: GlyphIcon(
                                  Glyph.add,
                                  color: Hue.white,
                                  weight: 2,
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GlyphIcon(
                          icon,
                          color: item == tab ? Hue.positive : Hue.muted,
                          tinted: item == tab,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            color: item == tab ? Hue.positive : Hue.muted,
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
