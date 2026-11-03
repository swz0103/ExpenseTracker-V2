import 'package:flutter/material.dart';

import '../../../../core/look/app_mark.dart';
import '../../../../core/look/theme.dart';

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
    this.arrive = false,
  });

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
    duration: const Duration(milliseconds: 620),
  );

  /// How many dots stand in for nothing typed yet.
  static const _room = 6;

  /// The most dots shown; a longer password keeps the row this wide.
  static const _most = 14;

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
  }

  @override
  void dispose() {
    _focus.dispose();
    _settle.dispose();
    super.dispose();
  }

  /// Brings the keyboard up for the password.
  void _type() {
    if (mounted && !widget.busy) _focus.requestFocus();
  }

  void _submit() {
    if (widget.busy || widget.password.text.isEmpty) return;
    widget.onSubmit();
  }

  /// A soft light behind the mark, on the tinted top of the page.
  static const _halo = Shade(0xBFFFFFFF, 0x1A72A8BC);

  /// The group's fixed parts, top to bottom, so the mark's place is known
  /// before it is laid out (it moves there from the middle).
  static const _mark = 72.0;
  static const _height = _mark + 14 + 32 + 22 + 20 + 34 + 58 + 6 + 44;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Hue.paper,
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
                  colors: [Hue.hero, Hue.hero, Hue.paper],
                  stops: [0, 0.45, 0.78],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              final top = ((box.maxHeight - _height) / 2).clamp(0.0, 1e9);
              // From the middle of the screen, where the opening drew it.
              final markY = inset.top + top + _mark / 2;
              final from = screen.height / 2 - markY;
              final grow = 112 / _mark;
              return SingleChildScrollView(
                child: SizedBox(
                  height: box.maxHeight < _height ? _height : box.maxHeight,
                  child: Stack(
                    children: [
                      Positioned(
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
                                colors: [_halo, Color(0x00FFFFFF)],
                                stops: [0, 0.68],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: top,
                        child: Column(
                          children: [
                            Transform.translate(
                              offset: Offset(0, from * (1 - move)),
                              child: Transform.scale(
                                scale: grow + (1 - grow) * move,
                                child: Semantics(
                                  label: '記帳本',
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: const AppMark(size: _mark),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            _rise(come, _name()),
                            const SizedBox(height: 22),
                            _rise(come, _dots()),
                            _rise(come, _problem()),
                            _rise(come, _fingerprint()),
                            const SizedBox(height: 6),
                            _rise(come, _forgot()),
                          ],
                        ),
                      ),
                      if (back != null)
                        Positioned(
                          left: 8,
                          top: 4,
                          child: _rise(
                            come,
                            TextButton(
                              onPressed: widget.busy ? null : back,
                              style: TextButton.styleFrom(
                                foregroundColor: Hue.muted,
                              ),
                              child: const Text('返回'),
                            ),
                          ),
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

  Widget _name() => const SizedBox(
    height: 32,
    child: Text(
      '記帳本',
      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 1.8),
    ),
  );

  /// The password as dots: filled for each letter typed, hollow for the
  /// room left; a tap brings the keyboard back.
  Widget _dots() => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: _type,
    child: SizedBox(
      height: 20,
      width: double.infinity,
      child: ListenableBuilder(
        listenable: widget.password,
        builder: (context, _) {
          final typed = widget.password.text.length;
          final filled = typed > _most ? _most : typed;
          final hollow = filled >= _most
              ? 0
              : filled >= _room
              ? 1
              : _room - filled;
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
                    color: i < filled ? Hue.accent : null,
                    border: i < filled
                        ? null
                        : Border.all(
                            color: wrong ? Hue.danger : Hue.accentRule,
                            width: 1.6,
                          ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );

  Widget _problem() {
    final text = widget.problem;
    return SizedBox(
      height: 34,
      child: Center(
        child: text == null || text.isEmpty
            ? null
            : Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Hue.danger),
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
                  color: Hue.accent,
                ),
              )
            : device == null
            ? null
            : Material(
                color: Hue.accentTrack,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: device,
                  child: const SizedBox.square(
                    dimension: 58,
                    child: Icon(
                      Icons.fingerprint,
                      size: 30,
                      color: Hue.accent,
                      semanticLabel: '用指紋或臉部解鎖',
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _forgot() => SizedBox(
    height: 44,
    child: Center(
      child: TextButton(
        onPressed: widget.busy ? null : widget.onRecovery,
        style: TextButton.styleFrom(
          foregroundColor: Hue.muted,
          textStyle: const TextStyle(fontSize: 13),
        ),
        child: const Text('忘記密碼？'),
      ),
    ),
  );

  /// The field the keyboard types into: one pixel, see-through; the dots
  /// show what is in it.
  Widget _field() => Opacity(
    opacity: 0,
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
          readOnly: widget.busy,
          onSubmitted: (_) => _submit(),
        ),
      ),
    ),
  );
}
