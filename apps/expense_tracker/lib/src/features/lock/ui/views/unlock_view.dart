import 'package:flutter/material.dart';

import '../../../../core/design_system/app_mark.dart';
import '../../../../core/design_system/theme.dart';
import '../../../../core/design_system/components/buttons.dart';
import '../../../../core/design_system/keys.dart';
import '../../../../core/design_system/shape.dart';
import '../../../../core/design_system/spacing.dart';
import '../../../../core/design_system/motion.dart';
import '../../../../core/formatting/words.dart';

/// Opening a ledger with its password, on the welcome's ground: the mark
/// and the name, the password as dots that fill in as it is typed (the
/// field itself is not shown; the keyboard comes up by itself and its
/// enter key opens), the fingerprint under them when the phone can, and
/// 忘記密碼？ for the recovery code.
///
/// With [arrive], it follows the opening animation: the mark moves up
/// from the middle and shrinks into place while the rest comes in.
class UnlockView extends StatefulWidget {
  const UnlockView({
    super.key,
    required this.password,
    required this.busy,
    required this.onSubmit,
    required this.onRecovery,
    this.onDevice,
    this.onBack,
    this.problem,
    this.waiting,
    this.arrive = false,
  });

  /// Said in place of [problem] while the password may not be typed: the
  /// wait after too many wrong ones, counting down. The fingerprint and
  /// the recovery link stay as they are.
  final String? waiting;

  final TextEditingController password;
  final bool busy;
  final VoidCallback onSubmit;

  /// Uses the recovery code instead: 忘記密碼？.
  final VoidCallback onRecovery;

  /// Asks for the fingerprint or face; none when the phone cannot.
  final VoidCallback? onDevice;

  /// Back to the first screen; none when there is nothing to go back to.
  final VoidCallback? onBack;
  final String? problem;

  /// Just after the opening animation, which this carries on from.
  final bool arrive;

  @override
  State<UnlockView> createState() => _UnlockViewState();
}

class _UnlockViewState extends State<UnlockView>
    with SingleTickerProviderStateMixin {
  final _focus = FocusNode();

  /// The mark settling and the rest coming in, after the opening.
  late final _settle = AnimationController(
    vsync: this,
    // Exception to motion: not run while motion is off (see build).
    duration: Motion.long4,
  );

  /// The most dots shown; a longer password keeps the row this wide.
  static const _most = 14;

  /// A dot with its gap, wide.
  static const _dotSlot = 11.0 + 13.0;

  /// What a screen reader is told, once, when a wait begins and when it
  /// ends: the countdown itself changes every second and is not read out.
  String _said = '';

  @override
  void initState() {
    super.initState();
    if (!widget.arrive) {
      _settle.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) => _type());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settle.isAnimating || _settle.isCompleted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _settle.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) => _type());
    } else {
      _settle.forward().whenComplete(_type);
    }
  }

  @override
  void didUpdateWidget(UnlockView old) {
    super.didUpdateWidget(old);
    // A wrong password: the dots empty for the next try.
    if (widget.problem != null && old.problem != widget.problem) {
      widget.password.clear();
      _type();
    }
    // The wait began: what was typed goes. It ended: the keyboard is
    // back for the next try.
    if (widget.waiting != null && old.waiting == null) {
      widget.password.clear();
      _focus.unfocus();
      _said = widget.waiting!;
    } else if (widget.waiting == null && old.waiting != null) {
      _said = '可以再輸入密碼了';
      _type();
    } else if (widget.problem != null && old.problem != widget.problem) {
      _said = widget.problem!;
    } else if (widget.problem == null && old.problem != null) {
      // Cleared, so the same words said again are read again.
      _said = '';
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _settle.dispose();
    super.dispose();
  }

  /// Brings the keyboard up for the password.
  void _type() {
    if (mounted && !widget.busy && widget.waiting == null) {
      _focus.requestFocus();
    }
  }

  void _submit() {
    if (widget.busy || widget.waiting != null) return;
    if (widget.password.text.isEmpty) return;
    widget.onSubmit();
  }

  /// The group's fixed parts, top to bottom, so the mark's place is known
  /// before it is laid out (it moves there from the middle).
  static const _mark = 72.0;
  static const _nameBox = 32.0;
  static const _problemBox = 34.0;
  static const _height =
      _mark + 14 + _nameBox + 22 + 20 + _problemBox + 58 + 6 + Space.target;

  /// [_height] with the words' boxes grown for the text size.
  double _heightFor(double scale) =>
      _height + (scale - 1) * (_nameBox + _problemBox + Space.target);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: AnimatedBuilder(
        animation: _settle,
        builder: (context, _) => _page(),
      ),
    );
  }

  Widget _page() {
    final move = Curves.easeInOutCubic.transform(_settle.value);
    final come = Curves.easeOutCubic.transform(
      ((_settle.value - 0.35) / 0.65).clamp(0.0, 1.0),
    );
    final screen = MediaQuery.sizeOf(context);
    final inset = MediaQuery.paddingOf(context);
    final back = widget.onBack;
    final scale = MediaQuery.textScalerOf(context).scale(1.0);
    final height = _heightFor(scale < 1 ? 1 : scale);
    return Stack(
      children: [
        Positioned.fill(
          child: Opacity(
            opacity: move,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.hero, AppColors.hero, AppColors.paper],
                  stops: [0, 0.45, 0.78],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              final top = ((box.maxHeight - height) / 2).clamp(0.0, 1e9);
              // From the middle of the screen, where the opening drew it.
              final markY = inset.top + top + _mark / 2;
              final from = screen.height / 2 - markY;
              return SingleChildScrollView(
                child: SizedBox(
                  height: box.maxHeight < height ? height : box.maxHeight,
                  child: Stack(
                    children: [
                      _halo(move, box, top),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: top,
                        child: _group(move, come, from),
                      ),
                      if (back != null)
                        Positioned(
                          left: 8,
                          top: 4,
                          child: _rise(come, _back(back)),
                        ),
                      // The password itself, typed into but not shown.
                      Positioned(left: 0, top: 0, child: _field()),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// A soft light behind the mark, on the tinted top of the page; it
  /// shows as the mark settles ([move]).
  Widget _halo(double move, BoxConstraints box, double top) => Positioned(
    left: box.maxWidth / 2 - 100,
    top: top + _mark / 2 - 100,
    child: Opacity(
      opacity: move,
      child: Container(
        width: 200,
        height: 200,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [AppColors.halo, AppColors.none],
            stops: [0, 0.68],
          ),
        ),
      ),
    ),
  );

  /// The mark and everything under it, top to bottom: the mark moves up
  /// [from] the middle and shrinks as [move] goes to 1, the rest rises
  /// in with [come].
  Widget _group(double move, double come, double from) {
    final grow = 112 / _mark;
    return Column(
      children: [
        Transform.translate(
          offset: Offset(0, from * (1 - move)),
          child: Transform.scale(
            scale: grow + (1 - grow) * move,
            // The name under it says it; the mark is not read as well.
            child: ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.large),
                child: const AppMark(size: _mark),
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.s4),
        _rise(come, _name()),
        const SizedBox(height: Space.s6),
        _rise(come, _dots()),
        _rise(come, _problem()),
        _rise(come, _fingerprint()),
        const SizedBox(height: Space.s2),
        _rise(come, _forgot()),
      ],
    );
  }

  /// 返回, to the first screen.
  Widget _back(VoidCallback back) => TextButton(
    key: Keys.back,
    onPressed: widget.busy ? null : back,
    style: wordButton(AppColors.muted),
    child: const Text(Words.back),
  );

  /// [child] coming up into place as [come] goes from 0 to 1; it takes
  /// no taps until it is there.
  Widget _rise(double come, Widget child) => IgnorePointer(
    ignoring: come < 1,
    child: Opacity(
      opacity: come,
      child: Transform.translate(
        offset: Offset(0, 16 * (1 - come)),
        child: child,
      ),
    ),
  );

  Widget _name() => ConstrainedBox(
    constraints: BoxConstraints(minHeight: _nameBox),
    child: Text(
      '記帳本',
      style: TextStyle(
        fontSize: TextSize.large,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.8,
      ),
    ),
  );

  /// The password as dots: filled for each letter typed, then one hollow
  /// for the next. No row of hollow dots stands for a length, so none is
  /// suggested; a tap brings the keyboard back.
  Widget _dots() => ExcludeSemantics(
    // The password field is what a screen reader finds; the dots show it.
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _type,
      child: SizedBox(
        height: 20,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, box) => _dotRow(
            // Fewer dots on a narrow screen, so the row always fits.
            ((box.maxWidth / _dotSlot).floor() - 1).clamp(1, _most),
          ),
        ),
      ),
    ),
  );

  Widget _dotRow(int most) => ListenableBuilder(
    listenable: widget.password,
    builder: (context, _) {
      final typed = widget.password.text.length;
      final filled = typed > most ? most : typed;
      final hollow = filled >= most ? 0 : 1;
      final wrong = widget.problem != null && typed == 0;
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < filled + hollow; i++)
            Container(
              width: 11,
              height: 11,
              margin: const EdgeInsets.symmetric(horizontal: 6.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < filled ? AppColors.accent : null,
                border: i < filled
                    ? null
                    : Border.all(
                        color: wrong ? AppColors.danger : AppColors.accentRule,
                        width: 1.6,
                      ),
              ),
            ),
        ],
      );
    },
  );

  Widget _problem() {
    final waiting = widget.waiting;
    final text = waiting ?? widget.problem;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _problemBox),
      child: Center(
        child: text == null || text.isEmpty
            // Read out when it changes: a wrong password, and the wait at
            // its start and its end; the second-by-second countdown below
            // is shown but not read.
            ? Semantics(liveRegion: true, label: _said, child: const SizedBox())
            : Semantics(
                liveRegion: true,
                label: _said,
                child: ExcludeSemantics(
                  child: Text(
                    text,
                    key: waiting == null ? null : Keys.unlockWait,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: TextSize.small,
                      color: AppColors.danger,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  /// The fingerprint on a soft round tint; a spinner while opening.
  Widget _fingerprint() {
    final device = widget.onDevice;
    return SizedBox(
      height: 58,
      child: Center(
        child: widget.busy
            ? const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppColors.accent,
                ),
              )
            : device == null
            ? null
            : Material(
                color: AppColors.accentTrack,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: Keys.fingerprint,
                  onTap: device,
                  child: const SizedBox.square(
                    dimension: 58,
                    child: Icon(
                      Icons.fingerprint,
                      size: 30,
                      color: AppColors.accent,
                      semanticLabel: '用生物辨識解鎖',
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _forgot() => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: Space.target),
    child: Center(
      child: TextButton(
        key: Keys.forgot,
        onPressed: widget.busy ? null : widget.onRecovery,
        style: wordButton(
          AppColors.muted,
          words: appFont.copyWith(fontSize: TextSize.small),
        ),
        child: const Text('忘記密碼？'),
      ),
    ),
  );

  /// The field the keyboard types into: one pixel, see-through; the dots
  /// show what is in it.
  Widget _field() => Opacity(
    opacity: 0,
    // Still in the semantics tree: it is the password field to TalkBack.
    alwaysIncludeSemantics: true,
    child: SizedBox(
      width: 1,
      height: 1,
      child: Semantics(
        label: '帳本密碼',
        child: TextField(
          controller: widget.password,
          focusNode: _focus,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          keyboardType: TextInputType.visiblePassword,
          textInputAction: TextInputAction.go,
          showCursor: false,
          enableInteractiveSelection: false,
          readOnly: widget.busy || widget.waiting != null,
          onSubmitted: (_) => _submit(),
        ),
      ),
    ),
  );
}
