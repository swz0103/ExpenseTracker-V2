part of 'accounts.dart';

/// The accounts as one stack of cards: the top strip of each, and the one
/// at [index] whole in front, at the bottom. A tap on a card behind
/// brings it to the front; a tap on the front one opens it.
///
/// Held, the stack turns into a wheel: every card whole on an upright
/// drum, the one in the middle facing out and the others tipping away
/// above and below it. A drag turns the drum with the finger; let go, it
/// runs on with the finger's speed and stops on a card, with a tick for
/// each card that passes. 完成, or a tap on the middle card, puts that
/// card in front and lays the stack down again.
class _Wallet extends StatefulWidget {
  const _Wallet({
    required this.ledger,
    required this.accounts,
    required this.index,
    required this.onShow,
    required this.onOpen,
  });

  final Ledger ledger;
  final List<Account> accounts;
  final int index;
  final ValueChanged<Account> onShow;
  final ValueChanged<Account> onOpen;

  @override
  State<_Wallet> createState() => _WalletState();
}

class _WalletState extends State<_Wallet> with SingleTickerProviderStateMixin {
  /// Where the drum stands, in cards: 2.0 is the third account facing out.
  late final _spin = AnimationController.unbounded(vsync: this)
    ..addListener(_ticked);
  var _turning = false;

  /// Where the drum stood when the finger went down, and where it was.
  var _from = 0.0;
  var _startY = 0.0;

  /// The card last passed, for one tick each.
  var _passed = 0;

  /// How far a finger moves to turn the drum by one card.
  static const _pace = 84.0;

  /// The angle between two cards on the drum, in degrees.
  static const _step = 30.0;

  int get _count => widget.accounts.length;
  int _wrap(int i) => ((i % _count) + _count) % _count;

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  void _ticked() {
    final near = _spin.value.round();
    if (near != _passed) {
      _passed = near;
      Haptics.selection();
    }
  }

  void _start() {
    Haptics.medium();
    _spin.value = widget.index.toDouble();
    _passed = widget.index;
    setState(() => _turning = true);
  }

  void _finish() {
    _spin.stop();
    final front = widget.accounts[_wrap(_spin.value.round())];
    setState(() => _turning = false);
    widget.onShow(front);
  }

  void _hold(double y) {
    _spin.stop();
    _from = _spin.value;
    _startY = y;
  }

  // Down brings the card above to the middle, as the finger turns it.
  void _move(double y) => _spin.value = _from + (y - _startY) / _pace;

  /// Runs on with the finger's speed, then settles on the nearest card.
  void _letGo(double speed) {
    final quiet = MediaQuery.disableAnimationsOf(context);
    // A slow let-go stays on the nearest card; only a real flick runs on,
    // and by no more than three cards, so it does not overshoot by one.
    final flick = speed.abs() < 500 ? 0.0 : (speed / _pace * 0.14);
    final target = (_spin.value + flick.clamp(-3.0, 3.0)).roundToDouble();
    if (quiet) {
      _spin.value = target;
      return;
    }
    final far = (target - _spin.value).abs();
    _spin.animateTo(
      target,
      duration: Duration(
        milliseconds: (220 + far * 110).clamp(220, 900).round(),
      ),
      curve: Curves.easeOutCubic,
    );
  }

  /// Turns the drum to the card at [i], the nearer way round.
  void _turnTo(int i) {
    var d = (i - _spin.value) % _count;
    if (d > _count / 2) d -= _count;
    _spin.animateTo(
      (_spin.value + d).roundToDouble(),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final (strip, front) = cardHeights(context);
    final rest = (strip - 12) * (_count - 1) + front;
    final quiet = MediaQuery.disableAnimationsOf(context);
    final wheel = front * 2.9;
    return GestureDetector(
      // A screen reader taps each card instead.
      excludeFromSemantics: true,
      onLongPressStart: _count < 2 || _turning
          ? null
          : (d) {
              _start();
              _hold(d.globalPosition.dy);
            },
      onLongPressMoveUpdate: _turning
          ? (d) => _move(d.globalPosition.dy)
          : null,
      onLongPressEnd: _turning
          ? (d) => _letGo(d.velocity.pixelsPerSecond.dy)
          : null,
      // Only while turning: otherwise the page scrolls as usual.
      onVerticalDragStart: _turning ? (d) => _hold(d.globalPosition.dy) : null,
      onVerticalDragUpdate: _turning ? (d) => _move(d.globalPosition.dy) : null,
      onVerticalDragEnd: _turning
          ? (d) => _letGo(d.velocity.pixelsPerSecond.dy)
          : null,
      child: AnimatedSize(
        duration: quiet ? Duration.zero : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: _turning
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('上下滑動轉卡', style: mutedSmall)),
                      TextButton(
                        key: Keys.walletDone,
                        onPressed: _finish,
                        style: wordButton(Hue.accent),
                        child: const Text('完成'),
                      ),
                    ],
                  ),
                  SizedBox(height: wheel, child: _drum(front, wheel)),
                ],
              )
            : SizedBox(height: rest, child: _stack(strip, front)),
      ),
    );
  }

  /// Every card whole on an upright drum around the one at [_spin].
  Widget _drum(double front, double height) {
    // A drum smaller than the cards' own spacing would need, so the
    // cards beside the middle one tuck behind it and the whole wheel
    // stays a little over two cards tall.
    final radius = front * 1.15;
    return AnimatedBuilder(
      animation: _spin,
      builder: (context, _) {
        final at = _spin.value;
        double offset(int i) {
          var d = (i - at) % _count;
          if (d > _count / 2) d -= _count;
          return d;
        }

        // The far ones first, so the near ones are drawn over them.
        final order = [for (var i = 0; i < _count; i++) i]
          ..sort((a, b) => offset(b).abs().compareTo(offset(a).abs()));
        return ClipRect(
          child: Stack(
            children: [
              for (final i in order)
                if ((offset(i) * _step).abs() < 80)
                  Positioned(
                    left: 10,
                    right: 10,
                    top: (height - front) / 2,
                    height: front,
                    child: _onDrum(i, offset(i), radius),
                  ),
            ],
          ),
        );
      },
    );
  }

  Widget _onDrum(int i, double offset, double radius) {
    final angle = offset * _step * pi / 180;
    final a = widget.accounts[i];
    // Every card as clear as the middle one: no fading at the sides.
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0009)
        ..translateByDouble(0, 0, -radius, 1)
        ..rotateX(angle)
        ..translateByDouble(0, 0, radius, 1),
      child: AccountCard(
        ledger: widget.ledger,
        account: a,
        onTap: offset.abs() < 0.5 ? _finish : () => _turnTo(i),
      ),
    );
  }

  /// The stack at rest: the strips of the others, the front one whole.
  Widget _stack(double strip, double front) {
    final accounts = widget.accounts;
    final last = accounts.length - 1;
    final step = strip - 12;
    final quiet = MediaQuery.disableAnimationsOf(context);
    // In the drum's order from the front one: the next account just
    // behind it, the one after behind that, round to the one before.
    final at = widget.index;
    final order = [
      for (var k = accounts.length - 1; k >= 0; k--)
        accounts[(at + k) % accounts.length],
    ];
    return Stack(
      children: [
        for (final (i, a) in order.indexed)
          AnimatedPositioned(
            key: ValueKey(a.id),
            duration: quiet ? Duration.zero : const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            top: step * i,
            left: 0,
            right: 0,
            child: i == last
                ? AccountCard(
                    ledger: widget.ledger,
                    account: a,
                    onTap: () => widget.onOpen(a),
                  )
                : AccountCard(
                    ledger: widget.ledger,
                    account: a,
                    front: false,
                    onTap: () {
                      Haptics.selection();
                      widget.onShow(a);
                    },
                  ),
          ),
      ],
    );
  }
}
