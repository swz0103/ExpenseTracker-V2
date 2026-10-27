import 'package:flutter/material.dart';

import '../look/theme.dart';

/// A button a row shows when slid open.
final class SwipeAction {
  const SwipeAction(this.label, this.color, this.onTap);

  final String label;
  final Color color;
  final VoidCallback onTap;
}

/// A row that slides left to show [actions] (such as 編輯 and 刪除) and
/// stays open when let go. A tap anywhere else, on the row itself, or a
/// slide of another row closes it; only one row is open at a time. A
/// vertical drag still scrolls the list: only a horizontal one slides.
/// Screen readers get the actions as the row's own actions.
class SwipeActions extends StatefulWidget {
  const SwipeActions({
    super.key,
    required this.actions,
    required this.child,
    this.background = Hue.white,
  });

  final List<SwipeAction> actions;
  final Widget child;

  /// What the row is drawn on, so the buttons do not show through it.
  final Color background;

  /// Width of each button.
  static const buttonWidth = 76.0;

  @override
  State<SwipeActions> createState() => SwipeActionsState();
}

class SwipeActionsState extends State<SwipeActions>
    with SingleTickerProviderStateMixin {
  /// The row open now, closed when another opens.
  static final _open = ValueNotifier<SwipeActionsState?>(null);

  late final _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  double get _width => widget.actions.length * SwipeActions.buttonWidth;

  /// Whether the buttons show, even partly.
  bool get isOpen => _slide.value > 0;

  void open() {
    final other = _open.value;
    if (other != null && other != this) other.close();
    _open.value = this;
    _slide.animateTo(1, curve: Curves.easeOutCubic);
  }

  void close() {
    if (_open.value == this) _open.value = null;
    _slide.animateTo(0, curve: Curves.easeOutCubic);
  }

  void _start(DragStartDetails _) {
    final other = _open.value;
    if (other != null && other != this) other.close();
  }

  void _update(DragUpdateDetails details) {
    _slide.value -= (details.primaryDelta ?? 0) / _width;
  }

  void _end(DragEndDetails details) {
    final speed = details.primaryVelocity ?? 0;
    if (speed < -300 || (speed <= 300 && _slide.value > 0.5)) {
      open();
    } else {
      close();
    }
  }

  @override
  void dispose() {
    if (_open.value == this) _open.value = null;
    _slide.dispose();
    super.dispose();
  }

  Widget _buttons() => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      for (final a in widget.actions)
        SizedBox(
          width: SwipeActions.buttonWidth,
          child: Material(
            color: a.color,
            child: InkWell(
              onTap: () {
                close();
                a.onTap();
              },
              child: Center(
                child: ExcludeSemantics(
                  child: Text(
                    a.label,
                    style: const TextStyle(
                      color: Hue.onAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (widget.actions.isEmpty) return widget.child;
    return Semantics(
      customSemanticsActions: {
        for (final a in widget.actions)
          CustomSemanticsAction(label: a.label): a.onTap,
      },
      child: TapRegion(
        onTapOutside: (_) {
          if (isOpen) close();
        },
        child: GestureDetector(
          onHorizontalDragStart: _start,
          onHorizontalDragUpdate: _update,
          onHorizontalDragEnd: _end,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _slide,
              builder: (context, row) => Stack(
                children: [
                  // Built only while showing, so a closed row holds no
                  // hidden buttons.
                  if (isOpen) Positioned.fill(child: _buttons()),
                  Transform.translate(
                    key: const ValueKey('row'),
                    offset: Offset(-_slide.value * _width, 0),
                    child: Stack(
                      children: [
                        row!,
                        // While open, a tap on the row closes it rather
                        // than opening the entry.
                        if (isOpen)
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: close,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              // A Material, not a plain colour, so the row's own ink
              // still shows on it.
              child: Material(color: widget.background, child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}
