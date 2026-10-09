import 'package:flutter/material.dart';

import '../compose/composer.dart';
import '../demo/ledger.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import 'account_page.dart';
import 'accounts.dart';
import 'budgets.dart';
import 'categories_page.dart';
import 'entry_sheet.dart';
import 'investments.dart';
import 'ledger_page.dart';
import 'more.dart';
import 'nav.dart';
import 'overview.dart';
import 'recurring_page.dart';
import 'reports.dart';
import 'settings_page.dart';

enum _Tab { overview, ledger, accounts, more }

/// The app frame: the 日々記帳 bar on top, the page, and 總覽、紀錄、記一筆、
/// 帳戶、更多 along the bottom. Pages under 更多 and each account open in
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
    showEntry: _showEntry,
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
    final saved = await openComposer(
      context,
      widget.ledger,
      type: type,
      entry: entry,
    );
    if (saved == null || !mounted) return;
    showNote(
      context,
      entry == null ? '已記下' : '已更新',
      action: '查看',
      onAction: () => _showEntry(saved),
    );
  }

  Future<void> _showEntry(Entry entry) async {
    final ledger = widget.ledger;
    final choice = await showEntrySheet(context, ledger, entry);
    if (!mounted) return;
    if (choice == 'edit') {
      await _compose(entry: entry);
    } else if (choice == 'deleted') {
      final removed = ledger.remove(entry.id);
      if (removed == null) return;
      showNote(
        context,
        '已刪除「${entry.title}」',
        action: '復原',
        onAction: () => ledger.restore(removed),
      );
    }
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
          child: Column(
            children: [
              _TopBar(onSettings: () => _open(Pages.settings)),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: KeyedSubtree(
                    key: ValueKey((_tab, _page)),
                    child: _body(),
                  ),
                ),
              ),
            ],
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

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: Hue.positive, width: 1.6),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text(
              '日',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Hue.positive,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            '日々記帳',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Hue.line),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Hue.gold,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  '演示',
                  style: TextStyle(fontSize: 11, color: Hue.muted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '設定',
            onPressed: onSettings,
            icon: const Icon(Icons.tune, color: Hue.ink),
          ),
        ],
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
    (_Tab.overview, Icons.home_outlined, '總覽'),
    (_Tab.ledger, Icons.receipt_long_outlined, '紀錄'),
    (_Tab.accounts, Icons.account_balance_wallet_outlined, '帳戶'),
    (_Tab.more, Icons.more_horiz, '更多'),
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
          height: 64,
          child: Row(
            children: [
              for (final (i, (item, icon, label)) in _items.indexed) ...[
                if (i == 2)
                  Expanded(
                    child: InkResponse(
                      onTap: onRecord,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: const BoxDecoration(
                              color: Hue.positive,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.add, color: Hue.white),
                          ),
                          const Text(
                            '記一筆',
                            style: TextStyle(fontSize: 11, color: Hue.ink),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: InkResponse(
                    onTap: () => onTab(item),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icon,
                          color: item == tab ? Hue.positive : Hue.muted,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
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
