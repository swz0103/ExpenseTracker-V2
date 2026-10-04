import 'package:flutter/material.dart';

import 'book.dart';
import 'screens/accounts_screen.dart';
import 'screens/entry_editor.dart';
import 'screens/home_screen.dart';
import 'screens/more_screen.dart';
import 'screens/records_screen.dart';
import 'theme.dart';

/// The app's frame: home, records, add, accounts and more along the
/// bottom, as in the mock-ups.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.book, required this.reports});

  final Book book;

  /// The report screen, opened from 更多.
  final Widget reports;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _tab = 0;

  static const _tabs = [
    (Icons.home_outlined, '首頁'),
    (Icons.receipt_long_outlined, '記錄'),
    (Icons.account_balance_wallet_outlined, '帳戶'),
    (Icons.grid_view, '更多'),
  ];

  Future<void> _record(EntryKind kind) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => EntryEditor(book: widget.book, kind: kind),
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('已記下')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _tab,
          children: [
            HomeScreen(book: book),
            RecordsScreen(book: book),
            AccountsScreen(book: book),
            MoreScreen(reports: widget.reports),
          ],
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: Palette.card,
          border: Border(top: BorderSide(color: Palette.line)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 62,
            child: Row(
              children: [
                for (final (i, (icon, name)) in _tabs.indexed) ...[
                  if (i == 2)
                    Expanded(
                      child: Center(
                        child: IconButton.filled(
                          tooltip: '記一筆',
                          onPressed: () => _record(EntryKind.expense),
                          style: IconButton.styleFrom(
                            backgroundColor: Palette.clay,
                            foregroundColor: Palette.card,
                            minimumSize: const Size(48, 48),
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
    final color = selected ? Palette.clay : Palette.muted;
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
