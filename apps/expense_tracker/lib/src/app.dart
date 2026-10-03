import 'package:flutter/material.dart';

import 'screens/accounts_screen.dart';
import 'screens/month_screen.dart';
import 'screens/record_screen.dart';
import 'session.dart';

class ExpenseApp extends StatelessWidget {
  const ExpenseApp({super.key, required this.session});

  final AppSession session;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2F6F62),
        brightness: brightness,
      ),
      fontFamily: 'NotoSansTC',
      useMaterial3: true,
    );
    return MaterialApp(
      title: '記帳本',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: HomeShell(session: session),
    );
  }
}

/// Three tabs for now: accounts, recording, and this month.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.session});

  final AppSession session;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  var _tab = 0;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: _tab,
            children: [
              AccountsScreen(session: session),
              RecordScreen(
                session: session,
                onSaved: () => setState(() => _tab = 0),
              ),
              MonthScreen(session: session),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (index) => setState(() => _tab = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              label: '帳戶',
            ),
            NavigationDestination(
              icon: Icon(Icons.add_circle_outline),
              label: '記一筆',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              label: '本月',
            ),
          ],
        ),
      ),
    );
  }
}
