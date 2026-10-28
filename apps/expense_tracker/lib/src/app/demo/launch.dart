import 'package:flutter/material.dart';

import '../../core/ledger/ledger.dart';
import '../../core/look/app_mark.dart';
import '../../core/look/theme.dart';
import '../../core/preferences.dart';
import '../../core/quick_action.dart';
import '../../features/lock/ui/views/lock_parts.dart';
import '../../features/lock/ui/views/unlock_view.dart';
import '../../features/lock/ui/views/welcome_view.dart';
import '../../features/overview/model/home_widget.dart';
import '../../features/settings/model/services.dart';
import '../shell.dart';
import 'seed.dart';

/// How the preview's app opens, as a real one would for each person: a
/// ledger without a password goes straight in, one with a password asks
/// for it, and the very first time shows the welcome.
enum PreviewStart {
  plain('免密碼'),
  password('有密碼'),
  first('第一次');

  const PreviewStart(this.label);

  final String label;
}

/// The web preview from the phone's home screen on: the app's icon and
/// its two home-screen widgets (本月概況 and 記一筆), the opening
/// animation, the lock screen when there is one, then the app. The bar at
/// the bottom goes back home, as the phone's gesture does.
class PreviewLaunch extends StatefulWidget {
  const PreviewLaunch({super.key, required this.preferences});

  final Preferences preferences;

  @override
  State<PreviewLaunch> createState() => _PreviewLaunchState();
}

enum _Stage { home, splash, lock, app }

class _PreviewLaunchState extends State<PreviewLaunch> {
  var _stage = _Stage.home;
  var _start = PreviewStart.plain;

  /// The made-up book, kept while the app is closed and opened again.
  var _ledger = demoLedger();

  /// What a widget's button asked for, taken by the app once open.
  final _quick = ValueNotifier<QuickAction?>(null);
  final _password = TextEditingController();
  String? _problem;

  /// Started once: the welcome comes the first time only.
  var _started = false;

  @override
  void dispose() {
    _quick.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _open({QuickAction? quick}) async {
    _quick.value = quick;
    setState(() => _stage = _Stage.splash);
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    if (!mounted || _stage != _Stage.splash) return;
    final asks =
        _start == PreviewStart.password ||
        (_start == PreviewStart.first && !_started);
    setState(() {
      _password.clear();
      _problem = null;
      _stage = asks ? _Stage.lock : _Stage.app;
    });
  }

  void _home() => setState(() => _stage = _Stage.home);

  @override
  Widget build(BuildContext context) {
    final screen = switch (_stage) {
      _Stage.home => _HomeScreen(
        ledger: _ledger,
        start: _start,
        onStart: (start) => setState(() {
          _start = start;
          // 第一次 starts a fresh book, as a new phone would.
          if (start == PreviewStart.first) {
            _started = false;
            _ledger = demoLedger();
          }
        }),
        onOpen: _open,
      ),
      _Stage.splash => const LockSplash(),
      _Stage.lock => Scaffold(
        backgroundColor: Hue.paper,
        body: SafeArea(child: _lock()),
      ),
      _Stage.app => AppShell(
        ledger: _ledger,
        services: Services(
          preferences: widget.preferences,
          sample: demoLedger,
          quick: _quick,
        ),
      ),
    };
    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: KeyedSubtree(key: ValueKey(_stage), child: screen),
          ),
        ),
        if (_stage != _Stage.home)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _HomeHandle(onTap: _home),
          ),
      ],
    );
  }

  Widget _lock() {
    if (_start == PreviewStart.first && !_started) {
      return WelcomeView(
        busy: false,
        onStart: () => setState(() {
          _started = true;
          _stage = _Stage.app;
        }),
        onWithPassword: () => setState(() {
          _started = true;
          _start = PreviewStart.password;
          _stage = _Stage.app;
        }),
        onRestore: () => setState(() {
          _started = true;
          _stage = _Stage.app;
        }),
      );
    }
    void submit() {
      if (_password.text.isEmpty) {
        setState(() => _problem = '請輸入密碼（預覽裡任何密碼都可以）');
        return;
      }
      setState(() => _stage = _Stage.app);
    }

    return UnlockView(
      password: _password,
      busy: false,
      onSubmit: submit,
      onRecovery: () => setState(() => _stage = _Stage.app),
      onDevice: () => setState(() => _stage = _Stage.app),
      problem: _problem,
    );
  }
}

/// The phone's gesture bar: a tap goes back to the home screen.
class _HomeHandle extends StatelessWidget {
  const _HomeHandle({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    return Semantics(
      button: true,
      label: '回到主畫面',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: inset > 14 ? inset : 14,
          child: Center(
            child: Container(
              width: 120,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0x99000000),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A home screen: the time, the two widgets, a row of other apps and the
/// app's icon; under them, which way the preview's app opens.
class _HomeScreen extends StatelessWidget {
  const _HomeScreen({
    required this.ledger,
    required this.start,
    required this.onStart,
    required this.onOpen,
  });

  final Ledger ledger;
  final PreviewStart start;
  final ValueChanged<PreviewStart> onStart;
  final Future<void> Function({QuickAction? quick}) onOpen;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final snapshot = widgetSnapshot(ledger, WidgetFigures.amounts);
    const white = TextStyle(
      color: Colors.white,
      decoration: TextDecoration.none,
    );
    return Material(
      type: MaterialType.transparency,
      child: _wallpaper(padding, snapshot, white),
    );
  }

  Widget _wallpaper(
    EdgeInsets padding,
    Map<String, Object?>? snapshot,
    TextStyle white,
  ) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5E7F86), Color(0xFF8BA79A), Color(0xFFC9B99A)],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          padding.top + 24,
          20,
          padding.bottom + 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '9:41',
              style: white.copyWith(fontSize: 56, fontWeight: FontWeight.w300),
            ),
            Text(
              '${ledger.today.month} 月 ${ledger.today.day} 日',
              style: white.copyWith(fontSize: 16),
            ),
            const SizedBox(height: 24),
            _SummaryWidget(
              snapshot: snapshot,
              onOpen: () => onOpen(),
              onExpense: () => onOpen(quick: QuickAction.expense),
              onIncome: () => onOpen(quick: QuickAction.income),
            ),
            const SizedBox(height: 14),
            _QuickWidget(
              onOpen: () => onOpen(),
              onExpense: () => onOpen(quick: QuickAction.expense),
              onIncome: () => onOpen(quick: QuickAction.income),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                const _OtherApp(Icons.call_outlined, '電話'),
                const _OtherApp(Icons.chat_bubble_outline, '訊息'),
                const _OtherApp(Icons.photo_camera_outlined, '相機'),
                _AppIcon(onTap: () => onOpen()),
              ],
            ),
            const SizedBox(height: 18),
            // Preview only: which person's phone this is.
            Center(
              child: SegmentedButton<PreviewStart>(
                segments: [
                  for (final s in PreviewStart.values)
                    ButtonSegment(value: s, label: Text(s.label)),
                ],
                selected: {start},
                showSelectedIcon: false,
                onSelectionChanged: (picked) => onStart(picked.first),
                style: SegmentedButton.styleFrom(
                  backgroundColor: const Color(0x33FFFFFF),
                  foregroundColor: Colors.white,
                  selectedBackgroundColor: Colors.white,
                  selectedForegroundColor: Hue.ink,
                  side: const BorderSide(color: Color(0x66FFFFFF)),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '預覽：選擇打開 App 的情境',
              textAlign: TextAlign.center,
              style: white.copyWith(
                fontSize: 12,
                color: const Color(0xCCFFFFFF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The app's own icon and name; a tap opens it.
class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '記帳本',
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: const AppMark(size: 60),
            ),
            const SizedBox(height: 6),
            const Text(
              '記帳本',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Another app on the home screen, for its look only.
class _OtherApp extends StatelessWidget {
  const _OtherApp(this.icon, this.name);

  final IconData icon;
  final String name;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0x33FFFFFF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

/// The widget 本月概況 as the phone draws it (summary_widget.xml), with
/// the figures shown as amounts.
class _SummaryWidget extends StatelessWidget {
  const _SummaryWidget({
    required this.snapshot,
    required this.onOpen,
    required this.onExpense,
    required this.onIncome,
  });

  final Map<String, Object?>? snapshot;
  final VoidCallback onOpen;
  final VoidCallback onExpense;
  final VoidCallback onIncome;

  @override
  Widget build(BuildContext context) {
    final shown = snapshot;
    final progress = shown?['progress'] as int?;
    final detail = shown?['detail'] as String? ?? '';
    return _WidgetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: onOpen,
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  shown?['title'] as String? ?? '本月概況',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF5B6670),
                  ),
                ),
                Text(
                  shown?['figure'] as String? ?? '—',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E2428),
                  ),
                ),
                if (progress != null) ...[
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress / 100,
                      minHeight: 6,
                      color: const Color(0xFF5C9A83),
                      backgroundColor: const Color(0xFFDDE1DC),
                    ),
                  ),
                ],
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF5B6670),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          _WidgetButtons(onExpense: onExpense, onIncome: onIncome),
        ],
      ),
    );
  }
}

/// The widget 記一筆 (quick_widget.xml): the icon and the two buttons.
class _QuickWidget extends StatelessWidget {
  const _QuickWidget({
    required this.onOpen,
    required this.onExpense,
    required this.onIncome,
  });

  final VoidCallback onOpen;
  final VoidCallback onExpense;
  final VoidCallback onIncome;

  @override
  Widget build(BuildContext context) {
    return _WidgetCard(
      padding: 8,
      child: Row(
        children: [
          GestureDetector(onTap: onOpen, child: const AppMark(size: 40)),
          const SizedBox(width: 8),
          Expanded(
            child: _WidgetButtons(onExpense: onExpense, onIncome: onIncome),
          ),
        ],
      ),
    );
  }
}

class _WidgetCard extends StatelessWidget {
  const _WidgetCard({required this.child, this.padding = 12});

  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: const Color(0xF2F3F4F1),
        borderRadius: BorderRadius.circular(24),
      ),
      // Merged, not replaced: the app's fonts (Chinese among them) stay.
      child: DefaultTextStyle.merge(
        style: const TextStyle(decoration: TextDecoration.none),
        child: child,
      ),
    );
  }
}

/// ＋ 記支出 and ＋ 記收入, as the widgets draw them.
class _WidgetButtons extends StatelessWidget {
  const _WidgetButtons({required this.onExpense, required this.onIncome});

  final VoidCallback onExpense;
  final VoidCallback onIncome;

  @override
  Widget build(BuildContext context) {
    Widget button(String label, Color color, VoidCallback onTap) => Expanded(
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ExcludeSemantics(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Row(
      children: [
        button('＋ 記支出', const Color(0xFFB5523E), onExpense),
        const SizedBox(width: 8),
        button('＋ 記收入', const Color(0xFF2F7A65), onIncome),
      ],
    );
  }
}
