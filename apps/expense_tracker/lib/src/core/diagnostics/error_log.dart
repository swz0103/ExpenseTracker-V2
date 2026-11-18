import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kReleaseMode;
import 'package:flutter/services.dart' show PlatformException;

import '../../core/time/app_clock.dart';

/// What did not work, kept for 設定 › 關於 › 診斷 so a fault can be seen and
/// exported instead of passing unseen. Only an error's type and a short
/// message cleaned of anything the person wrote are kept (names, notes,
/// amounts, paths), and nothing is printed in a release build.
final class ErrorLog {
  ErrorLog._();

  static final instance = ErrorLog._();

  /// Background work that did not finish, oldest first: what it was and
  /// when.
  final _problems = <(DateTime, String)>[];

  /// Where problems are kept across launches; none keeps them in memory.
  File? _log;

  /// The most problems kept.
  static const _kept = 50;

  /// Keeps problems in [file] from now on, and brings back those kept
  /// there before, so a fault before a crash can still be exported.
  void keepIn(File file) {
    _log = file;
    try {
      if (!file.existsSync()) return;
      for (final line in file.readAsLinesSync()) {
        final tab = line.indexOf('\t');
        final at = tab < 0 ? null : DateTime.tryParse(line.substring(0, tab));
        if (at == null) continue;
        _problems.add((at, _cleanKept(line.substring(tab + 1))));
      }
      _trim();
    } on Object {
      // An unreadable log starts again.
    }
  }

  void _trim() {
    if (_problems.length > _kept) {
      _problems.removeRange(0, _problems.length - _kept);
    }
  }

  /// The longest message kept of an error.
  static const _longest = 120;

  /// What is kept of [error]: its type and a short message, cleaned of
  /// what could be the person's own words (names, notes, amounts) or file
  /// paths, since the log can be exported.
  static String describe(Object error) {
    final said = switch (error) {
      FileSystemException(:final message) => message,
      PlatformException(:final code) => code,
      _ => '$error',
    };
    final code = error is FileSystemException ? error.osError?.errorCode : null;
    final errno = code == null ? '' : ' (errno $code)';
    return '${error.runtimeType}: ${_clean(said)}$errno';
  }

  static final _quoted = RegExp(r"""'[^']*'|"[^"]*"|「[^」]*」|“[^”]*”""");
  static final _path = RegExp(r'\S*[/\\]\S*');
  static final _foreign = RegExp(r'[^\x20-\x7e]+');
  // An errno is kept; it says what failed, not what was written.
  static final _digits = RegExp(r'(?<!errno )\d+');

  /// A problem as an older version kept it, with the whole error: what
  /// did not work, then the error, cleaned now.
  static String _cleanKept(String words) {
    final colon = words.indexOf('：');
    if (colon < 0) return _clean(words);
    return '${words.substring(0, colon)}：${_clean(words.substring(colon + 1))}';
  }

  /// One line of [text], without quoted words, paths, numbers or anything
  /// outside plain ASCII, at most [_longest] characters.
  static String _clean(String text) {
    var line = text.split('\n').first;
    line = line
        .replaceAll(_quoted, '…')
        .replaceAll(_path, '…')
        .replaceAll(_foreign, '…')
        .replaceAll(_digits, '#')
        .trim();
    if (line.length > _longest) line = '${line.substring(0, _longest)}…';
    return line;
  }

  /// Keeps that [what] did not work, for 設定 › 關於 › 診斷, rather than letting
  /// it pass unseen. Only the error's type and a cleaned message are kept,
  /// and nothing is printed in a release build.
  void record(String what, Object error) {
    if (!kReleaseMode) debugPrint('$what: $error');
    final words = '$what：${describe(error)}';
    final at = AppClock.now();
    _problems.add((at, words));
    _trim();
    final log = _log;
    if (log == null) return;
    try {
      log.writeAsStringSync(
        [for (final (t, w) in _problems) '${t.toIso8601String()}\t$w']
            .join('\n'),
        flush: true,
      );
    } on Object {
      // Kept in memory for this run.
    }
  }

  /// The problems kept, newest first.
  List<(DateTime, String)> get entries => _problems.reversed.toList();

  /// How many problems are kept.
  int get count => _problems.length;

  /// Each problem kept as one line of text, newest first, to export.
  String get text =>
      [for (final (at, what) in entries) '${at.toIso8601String()}  $what']
          .join('\n');
}
