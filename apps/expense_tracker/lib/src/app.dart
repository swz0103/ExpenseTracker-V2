import 'package:flutter/material.dart';

import 'session.dart';
import 'theme.dart';

/// The app shell. The screens are being rebuilt on the new architecture;
/// until then the shell shows [home], or that the ledger is ready.
class ExpenseApp extends StatelessWidget {
  const ExpenseApp({super.key, required this.session, this.home});

  final AppSession session;
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '記帳本',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      // Phones show no scroll bar; on the web one would cover the amounts.
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        scrollbars: false,
      ),
      home: home ?? const Scaffold(body: Center(child: Text('記帳本 V2：介面重建中'))),
    );
  }
}
