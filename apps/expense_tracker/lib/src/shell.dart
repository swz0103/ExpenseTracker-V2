import 'package:flutter/material.dart';

import 'theme.dart';

/// The app's frame, laid out like the old app: five places along the
/// bottom (home, entries, add, accounts, reports) and the rest in a side
/// menu. Screens not built yet say so.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.title,
    required this.home,
    required this.reports,
  });

  final String title;
  final Widget home;

  /// Brings its own app bar.
  final Widget reports;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _tab = 0;

  static const _tabs = [
    (Icons.calendar_today_outlined, '首頁'),
    (Icons.receipt_long_outlined, '明細'),
    (Icons.account_balance_wallet_outlined, '帳戶'),
    (Icons.insights_outlined, '報表'),
  ];

  static const _menu = [
    (Icons.category_outlined, '分類'),
    (Icons.savings_outlined, '預算'),
    (Icons.event_repeat_outlined, '定期記帳'),
    (Icons.show_chart, '股票'),
    (Icons.currency_exchange, '匯率'),
    (Icons.sell_outlined, '標籤'),
  ];

  void _later(String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('「$what」還在製作中')));
  }

  @override
  Widget build(BuildContext context) {
    final titles = [widget.title, '明細', '帳戶', '報表'];
    return Scaffold(
      appBar: _tab == 3
          ? null
          : AppBar(
              title: Text(
                titles[_tab],
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
      drawer: Drawer(
        backgroundColor: Palette.paper,
        shape: const RoundedRectangleBorder(),
        child: SafeArea(
          child: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Text(
                  '記帳本',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final (icon, name) in _menu)
                ListTile(
                  leading: Icon(icon, color: Palette.muted),
                  title: Text(name),
                  onTap: () {
                    Navigator.of(context).pop();
                    _later(name);
                  },
                ),
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          widget.home,
          const _NotYet('明細'),
          const _NotYet('帳戶'),
          widget.reports,
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: Palette.card,
          border: Border(top: BorderSide(color: Palette.line)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                for (final (i, (icon, name)) in _tabs.indexed) ...[
                  if (i == 2)
                    Expanded(
                      child: Center(
                        child: IconButton.filled(
                          tooltip: '記一筆',
                          onPressed: () => _later('記一筆'),
                          style: IconButton.styleFrom(
                            backgroundColor: Palette.clay,
                            foregroundColor: Palette.card,
                          ),
                          icon: const Icon(Icons.add),
                        ),
                      ),
                    ),
                  Expanded(
                    child: _TabButton(
                      icon: icon,
                      name: name,
                      selected: i == _tab,
                      onTap: () => setState(() => _tab = i),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.icon,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Palette.ink : Palette.muted;
    return InkResponse(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 2),
          Text(
            name,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotYet extends StatelessWidget {
  const _NotYet(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '$name畫面製作中',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Palette.muted,
        ),
      ),
    );
  }
}
