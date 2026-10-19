import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/scheduler.dart';

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

  /// Keeps that [what] did not work, for 設定 › 效能, rather than letting
  /// it pass unseen.
  void problem(String what, Object error) {
    debugPrint('$what: $error');
    _problems.add((DateTime.now(), '$what：$error'));
    if (_problems.length > 20) _problems.removeAt(0);
  }

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
