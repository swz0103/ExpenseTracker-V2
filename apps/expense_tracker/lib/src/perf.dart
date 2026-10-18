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
    return [('載入帳本', loads), ('畫面（最近 ${frames.length} 格）', drawn)];
  }
}
