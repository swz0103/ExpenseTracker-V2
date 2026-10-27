import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/look/haptics.dart';
import '../core/look/theme.dart';
import '../core/preferences.dart';
import '../core/ui/privacy_cover.dart';

/// The app shell: the theme, light or dark, the scrolling and [home].
class ExpenseApp extends StatefulWidget {
  const ExpenseApp({
    super.key,
    this.home,
    this.frame,
    this.preferences,
    this.cover = false,
  });

  final Widget? home;

  /// Wraps every route, as the web preview's phone frame does.
  final TransitionBuilder? frame;

  /// Colours and taps felt; the defaults when none.
  final Preferences? preferences;

  /// Covers every screen, sheets and dialogs included, while the app is
  /// off the screen: on a phone, for the recent apps list.
  final bool cover;

  @override
  State<ExpenseApp> createState() => _ExpenseAppState();
}

class _ExpenseAppState extends State<ExpenseApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.preferences?.addListener(_follow);
    _follow(first: true);
  }

  @override
  void dispose() {
    widget.preferences?.removeListener(_follow);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => _follow();

  /// Applies the person's choices. A change of colours draws every screen
  /// again in place, so nothing open is lost (see [Shade.show]).
  void _follow({bool first = false}) {
    final preferences = widget.preferences;
    Haptics.on = preferences?.haptics ?? true;
    final system =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    final dark = switch (preferences?.appearance ?? Appearance.system) {
      Appearance.system => system,
      Appearance.light => false,
      Appearance.dark => true,
    };
    if (first) {
      Shade.dark = dark;
      return;
    }
    if (dark == Shade.dark) return;
    Shade.show(dark: dark);
    // The Material theme and the status bar follow on the next build.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final dark = Shade.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: MaterialApp(
        title: '記帳本',
        debugShowCheckedModeBanner: false,
        // Every word the framework shows is Traditional Chinese, as the
        // app's own are.
        locale: const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hant',
          countryCode: 'TW',
        ),
        supportedLocales: const [
          Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hant',
            countryCode: 'TW',
          ),
        ],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: appTheme(),
        // No scroll bar (on the web one would cover the amounts), and a
        // list stops at its end: no stretch or bounce, as a web page would
        // do.
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          scrollbars: false,
          overscroll: false,
          physics: const ClampingScrollPhysics(),
        ),
        builder: (context, child) {
          final framed =
              widget.frame?.call(context, child) ??
              child ??
              const SizedBox.shrink();
          return widget.cover ? PrivacyCover(child: framed) : framed;
        },
        home: widget.home ?? const Scaffold(body: Center(child: Text('記帳本'))),
      ),
    );
  }
}
