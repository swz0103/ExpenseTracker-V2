import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kReleaseMode;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show PlatformException;

/// How fast this phone runs the app: the last ledger loads and recent
/// frames, shown under 設定 › 效能 so a real phone can be measured.
final class Perf {
  Perf._();

  static final instance = Perf._();

  /// The last loads of the ledger, in milliseconds.
  final _loads = <int>[];

  /// The slower of build and raster of each recent frame, in
  /// microseconds.
  final _frames = <int>[];

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

  /// Keeps that [what] did not work, for 設定 › 效能, rather than letting
  /// it pass unseen. Only the error's type and a cleaned message are kept,
  /// and nothing is printed in a release build.
  void problem(String what, Object error) {
    if (!kReleaseMode) debugPrint('$what: $error');
    final words = '$what：${describe(error)}';
    final at = DateTime.now();
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

  /// Everything kept, as text to export: the figures, then each problem.
  String get text => [
    for (final (name, figure) in report.take(2)) '$name：$figure',
    '',
    for (final (at, what) in problems) '${at.toIso8601String()}  $what',
  ].join('\n');

  /// The problems kept, newest first.
  List<(DateTime, String)> get problems => _problems.reversed.toList();

  /// Starts counting frames.
  void watchFrames() {
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final t in timings) {
        final build = t.buildDuration.inMicroseconds;
        final raster = t.rasterDuration.inMicroseconds;
        _frames.add(build > raster ? build : raster);
      }
      if (_frames.length > 600) _frames.removeRange(0, _frames.length - 600);
    });
  }

  /// Runs one load of the ledger and keeps how long it took.
  Future<T> timeLoad<T>(Future<T> Function() load) async {
    final watch = Stopwatch()..start();
    try {
      return await load();
    } finally {
      _loads.add(watch.elapsedMilliseconds);
      if (_loads.length > 20) _loads.removeAt(0);
    }
  }

  /// What 設定 › 效能 lists: a name and a figure.
  List<(String, String)> get report {
    final frames = [..._frames]..sort();
    String ms(int micros) => (micros / 1000).toStringAsFixed(1);
    var loads = '—';
    if (_loads.isNotEmpty) {
      final slowest = _loads.reduce((a, b) => a > b ? a : b);
      loads = '最近 ${_loads.last} ms · 最慢 $slowest ms';
    }
    var drawn = '—';
    if (frames.isNotEmpty) {
      final most = ms(frames[frames.length * 9 ~/ 10]);
      final slow = frames.where((f) => f > 16667).length;
      drawn = '九成在 $most ms 內 · 超過 16 ms 的 $slow 格';
    }
    String two(int n) => '$n'.padLeft(2, '0');
    return [
      ('載入帳本', loads),
      ('畫面（最近 ${frames.length} 格）', drawn),
      if (_problems.isEmpty) ('背景工作', '都正常'),
      for (final (at, what) in problems.take(5))
        ('${at.month}/${at.day} ${two(at.hour)}:${two(at.minute)}', what),
    ];
  }
}
