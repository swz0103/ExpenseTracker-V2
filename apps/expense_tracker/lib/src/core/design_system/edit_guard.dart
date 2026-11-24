import 'dart:async';

import 'package:flutter/material.dart';

import '../formatting/words.dart';
import 'components/buttons.dart';
import 'components/panels.dart';
import 'dialogs.dart';
import 'feedback.dart';
import 'keys.dart';
import 'theme.dart';

/// D83: every edit form's way out, the one block all of them use. While
/// the form holds [changed] edits, any way of leaving it (取消, back, a
/// tap beside the sheet, a swipe down) asks 要捨棄修改嗎？ first; 捨棄
/// leaves, 繼續編輯 stays, the sheet brought back up after a swipe. An
/// unchanged form leaves at once.
///
/// What the form saves (or deletes) leaves through [EditGuard.close],
/// which does not ask; its 取消 is [EditGuard.cancel], or the
/// [CancelButton].
class EditGuard extends StatefulWidget {
  const EditGuard({super.key, required this.changed, required this.child});

  /// Whether the form differs from what it opened with.
  final bool changed;

  final Widget child;

  /// Leaves the form [context] is in (any context on its route) with
  /// [result], without asking: what it holds was kept, or was meant to go.
  static void close<T>(BuildContext context, [T? result]) {
    final route = ModalRoute.of(context);
    if (route != null) _guards[route]?._let();
    Navigator.of(context).pop(result);
  }

  /// The guard holding each route, so [close] finds it from anywhere on
  /// the route, above the guard as well as under it.
  static final _guards = Expando<_EditGuardState>('EditGuard');

  /// 取消: leaves the form [context] is in, asking first while it holds
  /// changes.
  static Future<void> cancel(BuildContext context) =>
      Navigator.of(context).maybePop();

  @override
  State<EditGuard> createState() => _EditGuardState();
}

class _EditGuardState extends State<EditGuard> {
  /// Held on the form's route while it holds changes: a pop of the route
  /// takes this away instead of closing it, and asks.
  LocalHistoryEntry? _held;

  /// The route [_held] is on.
  ModalRoute<Object?>? _route;

  /// Taking [_held] away ourselves, not a pop.
  var _letting = false;

  /// The question is open.
  var _asking = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _later();
  }

  @override
  void didUpdateWidget(EditGuard old) {
    super.didUpdateWidget(old);
    if (old.changed != widget.changed) _later();
  }

  /// Holds or lets go after this frame: the route rebuilds as its history
  /// changes, which it may not while the form builds.
  void _later() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _follow();
  });

  void _follow() {
    final route = ModalRoute.of(context);
    // Not on a route already closing (a 捨棄, a save).
    if (route == null || !route.isActive) return;
    if (widget.changed && _held == null && !_asking) {
      final held = _held = LocalHistoryEntry(
        onRemove: _popped,
        impliesAppBarDismissal: false,
      );
      _route = route;
      EditGuard._guards[route] = this;
      route.addLocalHistoryEntry(held);
    } else if (!widget.changed) {
      _let();
    }
  }

  /// Lets the route close without asking.
  void _let() {
    final held = _held;
    if (held == null) return;
    _held = null;
    _letting = true;
    held.remove();
    _letting = false;
  }

  /// A pop took [_held] away: asked once the pop is done.
  void _popped() {
    if (_letting || _gone) return;
    _held = null;
    _asking = true;
    scheduleMicrotask(() {
      if (mounted) unawaited(_ask());
    });
  }

  Future<void> _ask() async {
    final route = ModalRoute.of(context);
    final drop = await confirm(
      context,
      Words.discardAsk,
      Words.discard,
      danger: true,
      cancel: Words.keepEditing,
    );
    _asking = false;
    if (!mounted) return;
    if (drop) {
      Navigator.of(context).pop();
      return;
    }
    if (route is SheetRoute) route.riseAgain();
    _follow();
  }

  /// Taken out of the screen.
  var _gone = false;

  @override
  void dispose() {
    // The route may be going with it: let go once the tree is free.
    _gone = true;
    final held = _held;
    final route = _route;
    _held = null;
    if (held != null && route != null) {
      scheduleMicrotask(() {
        if (route.isActive) held.remove();
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// An edit form's 取消, beside its main button: leaves, asking first
/// while the form holds changes ([EditGuard.cancel]).
class CancelButton extends StatelessWidget {
  const CancelButton({super.key, this.word = false});

  /// In words only, as a form's other word actions (刪除, 封存) beside a
  /// filled 儲存; a panel button otherwise.
  final bool word;

  @override
  Widget build(BuildContext context) {
    void cancel() => unawaited(EditGuard.cancel(context));
    if (word) {
      return TextButton(
        key: Keys.cancelEdit,
        onPressed: cancel,
        style: wordButton(AppColors.muted, minimumSize: const Size(64, 46)),
        child: const Text(Words.cancel),
      );
    }
    return PanelButton(Words.cancel, key: Keys.cancelEdit, onTap: cancel);
  }
}
