import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What [timeHeld] gave: what the run returned, the longest this isolate
/// was held while it ran (in microseconds), and how busy the host was
/// meanwhile ([load]), so a sample a busy machine stalled can be told
/// from one the code held.
final class Held<T> {
  const Held(this.result, this.heldUs, this.load, {this.rssBytes});

  final T result;
  final int heldUs;
  final Contention load;

  /// The process's resident memory as the sample ended, printed only: a
  /// figure that grows pair by pair says something is kept between
  /// samples, which each later sample pays for in collections.
  final int? rssBytes;

  /// Whether the host was too busy elsewhere for the sample to count.
  bool get contended => load.contended;
}

/// What [run] gave, and the longest this isolate was held while it ran
/// (in microseconds): a timer ticks every millisecond, and the widest gap
/// between two ticks is how long nothing else could run, a frame
/// included. Settled before and after, so the first and the last hold
/// are counted. [witness] reads how busy the host is before and after.
Future<Held<T>> timeHeld<T>(
  Future<T> Function() run, {
  HostWitness? witness,
}) async {
  final host = witness ?? HostWitness.ofThisHost;
  final before = host.read();
  final tick = Stopwatch()..start();
  var last = 0;
  var held = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 1), (_) {
    final now = tick.elapsedMicroseconds;
    if (now - last > held) held = now - last;
    last = now;
  });
  await Future<void>.delayed(const Duration(milliseconds: 20));
  held = 0;
  last = tick.elapsedMicroseconds;
  final result = await run();
  await Future<void>.delayed(const Duration(milliseconds: 20));
  timer.cancel();
  return Held(
    result,
    held,
    host.between(before, host.read()),
    rssBytes: ProcessInfo.currentRss,
  );
}

/// How busy the host was during one sample, from two [HostReading]s.
/// Each figure is null where the host gives no such reading.
final class Contention {
  const Contention({
    required this.wallUs,
    this.psiShare,
    this.stealShare,
    this.probeSlowdown,
    this.loadPerCore,
  });

  /// A sample on a host that gives no reading at all.
  static const unknown = Contention(wallUs: 0);

  final int wallUs;

  /// Of the sample's wall time, the share in which some runnable task on
  /// the host waited for a core (Linux PSI, `/proc/pressure/cpu` `some`).
  final double? psiShare;

  /// Of the host's CPU time, the share its hypervisor gave to others
  /// (`/proc/stat` steal).
  final double? stealShare;

  /// How much slower a fixed loop ran than the fastest seen (elsewhere
  /// than Linux, where neither counter exists).
  final double? probeSlowdown;

  /// The one-minute load per core, printed only: too slow a figure to
  /// judge one sample by.
  final double? loadPerCore;

  /// A sample counts as contended past any of these.
  static const psiLimit = 0.05;
  static const stealLimit = 0.01;
  static const probeLimit = 1.5;

  bool get contended =>
      (psiShare ?? 0) > psiLimit ||
      (stealShare ?? 0) > stealLimit ||
      (probeSlowdown ?? 0) > probeLimit;

  @override
  String toString() => [
    if (psiShare case final s?) 'psi ${_percent(s)}',
    if (stealShare case final s?) 'steal ${_percent(s)}',
    if (probeSlowdown case final s?) 'probe x${s.toStringAsFixed(2)}',
    if (loadPerCore case final l?) 'load/core ${l.toStringAsFixed(2)}',
  ].join(', ');
}

String _rss(Held<Object?> h) => switch (h.rssBytes) {
  final b? => ', rss ${b >> 20} MB',
  null => '',
};

String _percent(double share) => '${(share * 100).toStringAsFixed(1)}%';

/// One reading of the host's counters, taken before or after a sample.
typedef HostReading = ({
  int atUs,
  int? psiSomeUs,
  int? stealTicks,
  int? allTicks,
  int? probeUs,
  double? loadPerCore,
});

/// Reads how busy the host is around a sample: on Linux the kernel's
/// counters of time spent waiting for a core ([ProcWitness]), elsewhere a
/// fixed loop timed ([ProbeWitness]).
abstract interface class HostWitness {
  HostReading read();
  Contention between(HostReading before, HostReading after);

  /// The witness of the host the tests run on, made once.
  static final HostWitness ofThisHost = forHost();

  /// [ProcWitness] where `/proc/pressure/cpu` can be read, else
  /// [ProbeWitness].
  static HostWitness forHost() {
    final proc = ProcWitness();
    return proc.read().psiSomeUs != null ? proc : ProbeWitness();
  }
}

final _clock = Stopwatch()..start();

/// Linux: the PSI `some` total (µs some runnable task waited for a core,
/// host or container wide) and the steal ticks of `/proc/stat`. `file`
/// reads a file's text, or null where it cannot be read; a test feeds
/// readings through it.
final class ProcWitness implements HostWitness {
  ProcWitness({String? Function(String path)? file, int Function()? nowUs})
    : _file = file ?? _readFile,
      _nowUs = nowUs ?? (() => _clock.elapsedMicroseconds);

  final String? Function(String path) _file;
  final int Function() _nowUs;

  static String? _readFile(String path) {
    try {
      return File(path).readAsStringSync();
    } on Object {
      return null;
    }
  }

  static final _some = RegExp(r'^some .*total=(\d+)', multiLine: true);

  @override
  HostReading read() {
    final psi = _file('/proc/pressure/cpu');
    final some = psi == null ? null : _some.firstMatch(psi)?.group(1);
    final stat = _file('/proc/stat');
    int? steal;
    int? all;
    if (stat != null) {
      // cpu user nice system idle iowait irq softirq steal …
      final fields = stat.split('\n').first.split(RegExp(r'\s+'));
      if (fields.length > 8 && fields.first == 'cpu') {
        final ticks = [for (final f in fields.skip(1).take(8)) int.parse(f)];
        steal = ticks[7];
        all = ticks.fold<int>(0, (a, b) => a + b);
      }
    }
    final loadavg = _file('/proc/loadavg');
    final load = loadavg == null
        ? null
        : double.tryParse(loadavg.split(' ').first);
    return (
      atUs: _nowUs(),
      psiSomeUs: some == null ? null : int.parse(some),
      stealTicks: steal,
      allTicks: all,
      probeUs: null,
      loadPerCore: load == null ? null : load / Platform.numberOfProcessors,
    );
  }

  @override
  Contention between(HostReading before, HostReading after) {
    final wall = after.atUs - before.atUs;
    final psi = switch ((before.psiSomeUs, after.psiSomeUs)) {
      (final a?, final b?) when wall > 0 => (b - a) / wall,
      _ => null,
    };
    final steal = switch ((
      before.stealTicks,
      after.stealTicks,
      before.allTicks,
      after.allTicks,
    )) {
      (final s0?, final s1?, final t0?, final t1?) when t1 > t0 =>
        (s1 - s0) / (t1 - t0),
      _ => null,
    };
    return Contention(
      wallUs: wall,
      psiShare: psi,
      stealShare: steal,
      loadPerCore: after.loadPerCore,
    );
  }
}

/// Anywhere: a fixed integer loop of about 3 ms timed before and after a
/// sample; the slower of the two against the fastest seen is the sign of
/// a host busy elsewhere. `loop` runs a given number of rounds; a test
/// feeds times through it.
final class ProbeWitness implements HostWitness {
  ProbeWitness({int Function(int rounds)? loop}) : _loop = loop ?? _timedLoop {
    // Calibrated once: rounds doubled until the loop takes 3 ms.
    while (_loop(_rounds) < 3000 && _rounds < 1 << 30) {
      _rounds *= 2;
    }
  }

  final int Function(int rounds) _loop;
  var _rounds = 1 << 12;
  int? _fastest;

  static var _sink = 0;

  static int _timedLoop(int rounds) {
    final watch = Stopwatch()..start();
    var x = _sink | 1;
    for (var i = 0; i < rounds; i++) {
      x ^= x << 13 & 0xFFFFFFFF;
      x ^= x >> 17;
      x ^= x << 5 & 0xFFFFFFFF;
    }
    _sink = x;
    return watch.elapsedMicroseconds;
  }

  @override
  HostReading read() {
    final us = _loop(_rounds);
    if (_fastest == null || us < _fastest!) _fastest = us;
    return (
      atUs: _clock.elapsedMicroseconds,
      psiSomeUs: null,
      stealTicks: null,
      allTicks: null,
      probeUs: us,
      loadPerCore: null,
    );
  }

  @override
  Contention between(HostReading before, HostReading after) {
    final slower = [
      before.probeUs ?? 0,
      after.probeUs ?? 0,
    ].reduce((a, b) => a > b ? a : b);
    final fastest = _fastest;
    return Contention(
      wallUs: after.atUs - before.atUs,
      probeSlowdown: fastest == null || fastest == 0 ? null : slower / fastest,
    );
  }
}

/// One interleaved pair of a share gate: the work done apart and the
/// same work at once, a moment apart, so slow drift of the host's load
/// falls on both. Only the figures are kept, never what the work made
/// (see [shareOf]).
typedef SharePair = ({Held<Object?> apart, Held<Object?> whole});

/// How a share gate came out.
enum ShareVerdict { pass, fail, inconclusive }

/// Judged on the pairs whose samples were not contended: the median of
/// their ratios (apart held / whole held) against [limit], and, when
/// [apartMostUs] is given, the median of their apart holds against it.
final class ShareResult {
  ShareResult(this.pairs, {required this.limit, this.apartMostUs});

  final List<SharePair> pairs;
  final double limit;
  final int? apartMostUs;

  /// The fewest clean pairs a verdict is made on.
  static const leastClean = 3;

  static double _ratio(SharePair p) => p.apart.heldUs / p.whole.heldUs;
  static bool _contended(SharePair p) => p.apart.contended || p.whole.contended;

  late final List<SharePair> clean = [
    for (final p in pairs)
      if (!_contended(p)) p,
  ];

  late final List<double> cleanRatios = [for (final p in clean) _ratio(p)]
    ..sort();

  late final double? median = cleanRatios.isEmpty ? null : _median(cleanRatios);

  late final double? least = cleanRatios.isEmpty ? null : cleanRatios.first;

  /// The median of the clean pairs' apart holds, in µs.
  late final double? apartMedianUs = clean.isEmpty
      ? null
      : _median([for (final p in clean) p.apart.heldUs.toDouble()]..sort());

  int get contended => pairs.length - clean.length;

  ShareVerdict get verdict {
    if (clean.length < leastClean) return ShareVerdict.inconclusive;
    final overLimit = median! > limit;
    final overHold = apartMostUs != null && apartMedianUs! > apartMostUs!;
    return overLimit || overHold ? ShareVerdict.fail : ShareVerdict.pass;
  }

  static double _median(List<double> sorted) {
    final n = sorted.length;
    return n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
  }

  /// Every pair's figures, the witness's with them, and the verdict.
  String describe(String name) {
    final lines = [
      '$name: ${verdict.name.toUpperCase()}; ${clean.length} of '
          '${pairs.length} pairs clean (${Platform.numberOfProcessors} '
          'cores); median '
          '${median?.toStringAsFixed(3) ?? '-'}, least '
          '${least?.toStringAsFixed(3) ?? '-'}, limit $limit'
          '${apartMostUs == null ? '' : '; apart held median ${((apartMedianUs ?? 0) / 1000).toStringAsFixed(1)} ms, limit ${apartMostUs! ~/ 1000} ms'}',
      for (final (i, p) in pairs.indexed)
        '  pair ${i + 1}: apart ${p.apart.heldUs ~/ 1000} ms held '
            '(${p.apart.load}${_rss(p.apart)}), at once '
            '${p.whole.heldUs ~/ 1000} ms held '
            '(${p.whole.load}${_rss(p.whole)}), ratio '
            '${_ratio(p).toStringAsFixed(3)}'
            '${_contended(p) ? ' CONTENDED' : ''}',
    ];
    return lines.join('\n');
  }
}

/// How many interleaved pairs a share gate takes first, and the most it
/// takes when the host was busy for at least half of them.
const sharePairs = 5;
const shareMostPairs = 9;

/// A share gate's samples: [pairs] interleaved pairs of [apart] then
/// [whole] (apart first: posting at once leaves a heap of this isolate's
/// own to be collected, which the app never has before working apart).
/// When the verdict is not a pass and the witness marked at least half
/// the pairs contended, more pairs are taken up to [most] and all clean
/// pairs judged together; a failure on clean pairs gets no second chance.
Future<ShareResult> shareOf({
  required Future<Held<Object?>> Function() apart,
  required Future<Held<Object?>> Function() whole,
  required double limit,
  int? apartMostUs,
  int pairs = sharePairs,
  int most = shareMostPairs,
}) async {
  final taken = <SharePair>[];
  // What each run made is dropped at once: kept, the results of every
  // pair (an import's 100,000 entries each) pile up on this isolate's
  // heap, and each later sample pays a longer collection of it; the holds
  // apart grew pair by pair (17, 53, 94, 166, 184 ms on a quiet runner).
  Held<Object?> figures(Held<Object?> h) =>
      Held<Object?>(null, h.heldUs, h.load, rssBytes: h.rssBytes);
  Future<void> take() async {
    final a = figures(await apart());
    final w = figures(await whole());
    taken.add((apart: a, whole: w));
  }

  for (var i = 0; i < pairs; i++) {
    await take();
  }
  ShareResult judged() =>
      ShareResult(List.of(taken), limit: limit, apartMostUs: apartMostUs);
  var result = judged();
  if (result.verdict != ShareVerdict.pass &&
      result.contended * 2 >= result.pairs.length) {
    while (taken.length < most) {
      await take();
    }
    result = judged();
  }
  return result;
}

/// Passes, fails with every figure, or, when too few pairs were clean,
/// says so: a failure under `CI` (a red build that says why), a loud skip
/// elsewhere. Never a quiet pass.
void expectShare(
  ShareResult result,
  String name, {
  Map<String, String>? environment,
}) {
  final report = result.describe(name);
  // ignore: avoid_print
  print(report);
  switch (result.verdict) {
    case ShareVerdict.pass:
      return;
    case ShareVerdict.fail:
      fail(report);
    case ShareVerdict.inconclusive:
      final why =
          'INCONCLUSIVE: host contended (${result.clean.length} of '
          '${result.pairs.length} samples clean)\n$report';
      if ((environment ?? Platform.environment).containsKey('CI')) fail(why);
      markTestSkipped(why);
  }
}

/// The least of [tries] runs of [run]. Kept for the gates that are not
/// share gates of a hold (counted or µs-scale work).
Future<T> leastOf<T extends Comparable<Object>>(
  int tries,
  Future<T> Function() run,
) async {
  T? least;
  for (var i = 0; i < tries; i++) {
    final one = await run();
    if (least == null || one.compareTo(least) < 0) least = one;
  }
  return least!;
}

/// How many runs a gate takes the least of.
const gateTries = 3;
