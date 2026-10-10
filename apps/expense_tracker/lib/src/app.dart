import 'package:flutter/material.dart';

import 'look/theme.dart';
import 'session.dart';

/// The app shell. The screens are being rebuilt on the new architecture;
/// until then the shell shows [home], or that the ledger is ready.
class ExpenseApp extends StatelessWidget {
  const ExpenseApp({super.key, required this.session, this.home, this.frame});

  final AppSession session;
  final Widget? home;

  /// Wraps every route, as the web preview's phone frame does.
  final TransitionBuilder? frame;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '日々記帳',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      // Phones show no scroll bar; on the web one would cover the amounts.
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        scrollbars: false,
      ),
      builder: frame,
      home: home ?? const Scaffold(body: Center(child: Text('記帳本 V2：介面重建中'))),
    );
  }
}
