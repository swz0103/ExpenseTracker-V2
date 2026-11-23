import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../messages/diagnostics_messages.dart';
import '../time/app_clock.dart';
import 'error_log.dart';

/// What happens to a fault nothing caught, wherever it comes from: the
/// drawing of a screen (`FlutterError.onError`), anything else on the
/// main isolate, a zone's uncaught error included
/// (`PlatformDispatcher.onError`: the app runs in the root zone, so those
/// arrive there), and what the runtime reports for the isolate itself.
///
/// Each is kept in the [ErrorLog] with its stack and written at once.
/// While developing and in tests ([surface]) it is then shown as Flutter
/// would show it, never swallowed. In a release build nothing is printed
/// (the system log could carry the person's own words); the person is
/// told with one note ([tell]) that something went wrong and where it was
/// kept, at most once every [noteGap] however many faults follow, so a
/// screen that fails on every frame says it once and the app goes on.
final class UnhandledErrors {
  UnhandledErrors({
    required this.log,
    required this.tell,
    this.surface = !kReleaseMode,
  });

  final ErrorLog log;

  /// Says [DiagnosticsMessages.unforeseenNote] to the person; false when
  /// there was nowhere to say it yet.
  final bool Function(String note) tell;

  /// Whether faults are shown to the developer rather than told to the
  /// person: every build but a release one.
  final bool surface;

  /// The least time between two notes to the person.
  static const noteGap = Duration(minutes: 1);

  /// When the person was last told; null when never.
  DateTime? _told;

  /// A note is waiting for the frame to end.
  var _waiting = false;

  RawReceivePort? _isolate;
  AppLifecycleListener? _lifecycle;

  /// Takes every fault nothing catches from now on, and writes what the
  /// log holds when the app is left.
  void install() {
    FlutterError.onError = onFlutterError;
    PlatformDispatcher.instance.onError = onPlatformError;
    final port = _isolate = RawReceivePort(onIsolateError);
    Isolate.current.addErrorListener(port.sendPort);
    _lifecycle = AppLifecycleListener(
      onHide: () => unawaited(log.flush()),
      onPause: () => unawaited(log.flush()),
      onDetach: () => unawaited(log.flush()),
    );
  }

  /// Stops listening to the isolate and the app's coming and going; the
  /// two handlers are the caller's to put back.
  void dispose() {
    if (_isolate case final port?) {
      Isolate.current.removeErrorListener(port.sendPort);
      port.close();
    }
    _isolate = null;
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  /// A fault while a screen was built, laid out or drawn.
  void onFlutterError(FlutterErrorDetails details) {
    log.record(
      DiagnosticsMessages.screenError,
      details.exception,
      details.stack,
    );
    _after(() => FlutterError.presentError(details));
  }

  /// A fault nothing caught, outside the drawing of a screen. True when
  /// it was dealt with here; false leaves it to Flutter, which prints it.
  bool onPlatformError(Object error, StackTrace stack) {
    log.record(DiagnosticsMessages.unforeseenError, error, stack);
    _after(null);
    return !surface;
  }

  /// A fault the runtime reports for the isolate: the error and its
  /// stack, each as text.
  void onIsolateError(Object? message) {
    final [Object? error, Object? stack] = switch (message) {
      [final error, final stack] => [error, stack],
      _ => [message, null],
    };
    log.record(
      DiagnosticsMessages.isolateError,
      IsolateFault('$error'),
      stack == null ? StackTrace.empty : StackTrace.fromString('$stack'),
    );
    _after(() => debugPrint('${DiagnosticsMessages.isolateError}: $error'));
  }

  /// After a fault is kept: it is written now, then shown with [show] to
  /// the developer, or the person is told.
  void _after(VoidCallback? show) {
    unawaited(log.flush());
    if (surface) {
      show?.call();
      return;
    }
    final now = AppClock.now();
    if (_waiting) return;
    if (_told case final told? when now.difference(told) < noteGap) return;
    // A note cannot be put up while a frame is being built.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      _tell(now);
      return;
    }
    _waiting = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _waiting = false;
      _tell(AppClock.now());
    });
  }

  void _tell(DateTime now) {
    // Counted before it is said: a note that fails is not tried again
    // for the fault it causes.
    final before = _told;
    _told = now;
    try {
      if (!tell(DiagnosticsMessages.unforeseenNote)) _told = before;
    } on Object catch (error, stack) {
      // Kept like any other; the gap already counts from this try.
      log.record(DiagnosticsMessages.unforeseenError, error, stack);
    }
  }
}

/// What the runtime said of a fault of the isolate, as text.
final class IsolateFault implements Exception {
  const IsolateFault(this.said);

  final String said;

  @override
  String toString() => said;
}
