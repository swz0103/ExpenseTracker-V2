import 'package:flutter/material.dart';

import 'look/theme.dart';

/// The app shell: the theme, the scrolling and [home].
class ExpenseApp extends StatelessWidget {
  const ExpenseApp({super.key, this.home, this.frame});

  final Widget? home;

  /// Wraps every route, as the web preview's phone frame does.
  final TransitionBuilder? frame;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '記帳本',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      // No scroll bar (on the web one would cover the amounts), and a list
      // stops at its end: no stretch or bounce, as a web page would do.
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        scrollbars: false,
        overscroll: false,
        physics: const ClampingScrollPhysics(),
      ),
      builder: frame,
      home: home ?? const Scaffold(body: Center(child: Text('記帳本'))),
    );
  }
}
