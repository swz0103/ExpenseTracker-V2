import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../diagnostics/error_log.dart';
import '../time/app_clock.dart';

/// Copies a secret, such as the recovery code, as one: on Android flagged
/// sensitive, so the phone leaves it out of its clipboard preview and the
/// keyboard's suggestions, and taken off the clipboard after [keepFor]
/// when it is still what was copied (something copied since is left).
///
/// A phone does not let an app read the clipboard from the background:
/// when the time runs out there, it is cleared as soon as the app is back.
abstract final class SensitiveClipboard {
  /// Puts text on the clipboard flagged sensitive; set on Android
  /// (`ClipboardHandler.kt`). Without one, a plain copy.
  static Future<void> Function(String text)? platformCopy;

  /// How long a secret stays on the clipboard.
  static const keepFor = Duration(seconds: 60);

  static String? _copied;
  static DateTime? _at;
  static Timer? _timer;
  static AppLifecycleListener? _listener;

  /// Copies [text], to be taken off the clipboard after [keepFor].
  static Future<void> copy(String text) async {
    final copy = platformCopy;
    if (copy != null) {
      await copy(text);
    } else {
      await Clipboard.setData(ClipboardData(text: text));
    }
    _copied = text;
    _at = AppClock.now();
    _timer?.cancel();
    _timer = Timer(keepFor, () => unawaited(clearIfUnchanged()));
    _listener ??= AppLifecycleListener(onResume: _resumed);
  }

  static void _resumed() {
    final at = _at;
    if (_copied == null || at == null) return;
    if (AppClock.now().difference(at) >= keepFor) {
      unawaited(clearIfUnchanged());
    }
  }

  /// Takes the secret off the clipboard if it is still there. One that
  /// cannot be read now (the app in the background) is tried again when
  /// the app is back.
  static Future<void> clearIfUnchanged() async {
    final copied = _copied;
    if (copied == null) return;
    final ClipboardData? data;
    try {
      data = await Clipboard.getData(Clipboard.kTextPlain);
    } on PlatformException catch (error) {
      ErrorLog.instance.record('清除剪貼簿', error);
      return;
    }
    final text = data?.text;
    if (text == null) return;
    if (text == copied) await Clipboard.setData(const ClipboardData(text: ''));
    _forget();
  }

  static void _forget() {
    _copied = null;
    _at = null;
    _timer?.cancel();
    _timer = null;
    _listener?.dispose();
    _listener = null;
  }
}
