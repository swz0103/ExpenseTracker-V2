import 'package:flutter/material.dart';

import 'session.dart';

/// The app shell. The screens are being rebuilt on the new architecture;
/// until then the shell shows [home], or that the ledger is ready.
class ExpenseApp extends StatelessWidget {
  const ExpenseApp({super.key, required this.session, this.home});

  final AppSession session;
  final Widget? home;

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
      home:
          home ??
          const Scaffold(body: Center(child: Text('記帳本 V2：介面重建中'))),
    );
  }
}
