import 'package:flutter_test/flutter_test.dart';

import 'held.dart';

/// A witness that gives the readings it is handed, in turn.
final class _Fed implements HostWitness {
  _Fed(this.contentions);

  final List<Contention> contentions;
  var _i = 0;

  @override
  HostReading read() => (
    atUs: 0,
    psiSomeUs: null,
    stealTicks: null,
    allTicks: null,
    probeUs: null,
    loadPerCore: null,
  );

  @override
  Contention between(HostReading before, HostReading after) =>
      contentions[_i++ % contentions.length];
}

const _quiet = Contention(wallUs: 100000, psiShare: 0.01);
const _busy = Contention(wallUs: 100000, psiShare: 0.30);

Held<Object?> _held(int us, {bool busy = false}) =>
    Held<Object?>(null, us, busy ? _busy : _quiet);

SharePair _pair(int apartUs, int wholeUs, {bool busy = false}) =>
    (apart: _held(apartUs, busy: busy), whole: _held(wholeUs));

void main() {
  test('timeHeld gives the result and the longest hold', () async {
    final quiet = await timeHeld(() async => 7);
    expect(quiet.result, 7);

    final busy = await timeHeld(() async {
      final spin = Stopwatch()..start();
      while (spin.elapsedMilliseconds < 60) {}
      return 'done';
    });
    expect(busy.result, 'done');
    expect(busy.heldUs, greaterThanOrEqualTo(60000));
  });

  test('a spin held 60 ms on a host said to be busy is contended; '
      'the same on a quiet host is not', () async {
    Future<void> spin() async {
      final watch = Stopwatch()..start();
      while (watch.elapsedMilliseconds < 60) {}
    }

    final busy = await timeHeld(spin, witness: _Fed([_busy]));
    expect(busy.heldUs, greaterThanOrEqualTo(60000));
    expect(busy.contended, isTrue);
    final quiet = await timeHeld(spin, witness: _Fed([_quiet]));
    expect(quiet.heldUs, greaterThanOrEqualTo(60000));
    expect(quiet.contended, isFalse);
  });

  test('PSI is judged in the quiet windows beside a sample, not across '
      'the work, whose own threads add to it; steal across the whole', () {
    const quiet = Contention(wallUs: 150000, psiShare: 0.01);
    const ownWork = Contention(wallUs: 2000000, psiShare: 0.30);
    const busyAfter = Contention(wallUs: 150000, psiShare: 0.08);
    const span = Contention(wallUs: 2300000, psiShare: 0.2, stealShare: 0);
    final own = Contention.around(
      before: quiet,
      during: ownWork,
      after: quiet,
      whole: span,
    );
    expect(own.psiShare, 0.01);
    expect(own.psiDuring, 0.30);
    expect(own.contended, isFalse, reason: 'the work alone is not contention');
    expect(own.toString(), contains('psi during 30.0%'));
    final other = Contention.around(
      before: quiet,
      during: ownWork,
      after: busyAfter,
      whole: span,
    );
    expect(other.psiShare, 0.08);
    expect(other.contended, isTrue);
    final stolen = Contention.around(
      before: quiet,
      during: ownWork,
      after: quiet,
      // 2% of the CPU time went to other machines over the span.
      whole: const Contention(wallUs: 2300000, stealShare: 0.02),
    );
    expect(stolen.contended, isTrue);
  });

  test('a gate of one run per sample judges each figure by its median over '
      'the clean runs', () {
    Held<Map<String, double>> run(
      double share,
      double ms, {
      bool busy = false,
    }) => Held({'share': share, 'ms': ms}, 0, busy ? _busy : _quiet);
    final passing = MedianResult(
      [
        run(0.01, 900),
        run(0.02, 1000),
        // a stalled run, dropped
        run(0.50, 9000, busy: true),
        run(0.03, 1100),
      ],
      limits: {'share': 0.08, 'ms': 2600},
    );
    expect(passing.cleanCount, 3);
    expect(passing.median('share'), 0.02);
    expect(passing.median('ms'), 1000);
    expect(passing.verdict, ShareVerdict.pass);
    final failing = MedianResult(
      [run(0.01, 2700), run(0.02, 2650), run(0.03, 2900)],
      limits: {'share': 0.08, 'ms': 2600},
    );
    expect(failing.verdict, ShareVerdict.fail);
    expect(failing.describe('open'), contains('ms median 2700.000'));
    final contended = MedianResult(
      [for (var i = 0; i < 5; i++) run(0.01, 900, busy: true)],
      limits: {'share': 0.08},
    );
    expect(contended.verdict, ShareVerdict.inconclusive);
    expect(
      () => expectShare(contended, 'open', environment: const {'CI': 'true'}),
      throwsA(isA<TestFailure>()),
    );
  });

  test('mediansOf takes more runs only when half were contended', () async {
    var n = 0;
    final result = await mediansOf(
      run: () async => Held({'share': 0.01}, 0, n++ < 3 ? _busy : _quiet),
      limits: {'share': 0.08},
    );
    // 3 of the first 5 contended: taken on to 9, 6 clean.
    expect(result.taken, 9);
    expect(result.cleanCount, 6);
    expect(result.verdict, ShareVerdict.pass);
  });

  test('the Linux witness reads PSI and steal from /proc', () {
    var at = 0;
    final files = <String, String>{};
    final witness = ProcWitness(file: (path) => files[path], nowUs: () => at);
    files['/proc/pressure/cpu'] =
        'some avg10=1.00 avg60=1.00 avg300=1.00 total=1000000\n'
        'full avg10=0.00 avg60=0.00 avg300=0.00 total=0\n';
    files['/proc/stat'] = 'cpu  100 0 100 700 0 0 0 100 0 0\ncpu0 1 2 3\n';
    files['/proc/loadavg'] = '8.00 7.00 6.00 3/200 100\n';
    final before = witness.read();
    expect(before.psiSomeUs, 1000000);
    expect(before.stealTicks, 100);
    // 100 + 0 + 100 + 700 + 0 + 0 + 0 + 100
    expect(before.allTicks, 1000);
    at = 200000;
    // 8,000 µs waited in 200,000 µs: 4%, under the 5% limit.
    files['/proc/pressure/cpu'] = 'some avg10=1.00 total=1008000\n';
    // 2 steal ticks of 400 (100 + 0 + 200 + 898 + 100 + 0 + 0 + 102 =
    // 1,400, less 1,000): 0.5%.
    files['/proc/stat'] = 'cpu  100 0 200 898 100 0 0 102 0 0\n';
    final quiet = witness.between(before, witness.read());
    expect(quiet.wallUs, 200000);
    expect(quiet.psiShare, closeTo(0.04, 1e-9));
    expect(quiet.stealShare, closeTo(0.005, 1e-9));
    expect(quiet.contended, isFalse);

    // 20,000 µs waited in 200,000: 10%.
    at = 400000;
    final next = witness.read();
    files['/proc/pressure/cpu'] = 'some avg10=1.00 total=1028000\n';
    at = 600000;
    expect(witness.between(next, witness.read()).contended, isTrue);

    // Steal of 5 ticks in 100 (95 more idle, 5 more steal: 1,500): 5%.
    final s0 = witness.read();
    files['/proc/stat'] = 'cpu  100 0 200 993 100 0 0 107 0 0\n';
    final stolen = witness.between(s0, witness.read());
    expect(stolen.stealShare, closeTo(0.05, 1e-9));
    expect(stolen.contended, isTrue);
  });

  test('without /proc the Linux witness gives no figure', () {
    final witness = ProcWitness(file: (_) => null);
    final reading = witness.read();
    expect(reading.psiSomeUs, isNull);
    final none = witness.between(reading, witness.read());
    expect(none.psiShare, isNull);
    expect(none.stealShare, isNull);
    expect(none.contended, isFalse);
  });

  test('the probe witness marks a loop run 1.5 times slower than its '
      'fastest as contended', () {
    // Calibration: 1,000 µs for 4,096 rounds, then 3,000 for 8,192 (at
    // 3,000 µs the doubling stops); then four readings.
    final times = [1000, 3000, 3000, 3100, 3000, 5000];
    var i = 0;
    final witness = ProbeWitness(loop: (_) => times[i++]);
    final a = witness.read();
    final b = witness.read();
    // 3,100 / 3,000: 1.03.
    expect(witness.between(a, b).probeSlowdown, closeTo(1.033, 0.001));
    expect(witness.between(a, b).contended, isFalse);
    final c = witness.read();
    final d = witness.read();
    // 5,000 / 3,000: 1.67.
    expect(witness.between(c, d).probeSlowdown, closeTo(1.667, 0.001));
    expect(witness.between(c, d).contended, isTrue);
  });

  test('the median of clean pairs passes past a lone outlier', () {
    final result = ShareResult([
      // 10 / 400 = 0.025
      _pair(10000, 400000),
      // 12 / 400 = 0.03
      _pair(12000, 400000),
      // 40 / 400 = 0.1: one stalled pair the witness did not see
      _pair(40000, 400000),
      // 11 / 400 = 0.0275
      _pair(11000, 400000),
      // 13 / 400 = 0.0325
      _pair(13000, 400000),
    ], limit: 0.045);
    expect(result.clean, hasLength(5));
    // Sorted: 0.025, 0.0275, 0.03, 0.0325, 0.1.
    expect(result.median, closeTo(0.03, 1e-9));
    expect(result.least, closeTo(0.025, 1e-9));
    expect(result.verdict, ShareVerdict.pass);
  });

  test('a failure on clean pairs is a failure, however many contended '
      'pairs passed', () {
    final result = ShareResult([
      // 30 / 400 = 0.075 each, clean
      _pair(30000, 400000),
      _pair(30000, 400000),
      _pair(30000, 400000),
      // 4 / 400 = 0.01 each, contended: dropped, cannot rescue it
      _pair(4000, 400000, busy: true),
      _pair(4000, 400000, busy: true),
    ], limit: 0.045);
    expect(result.contended, 2);
    expect(result.median, closeTo(0.075, 1e-9));
    expect(result.verdict, ShareVerdict.fail);
  });

  test('a contended sample is dropped, never counted as a pass', () {
    final result = ShareResult([
      _pair(10000, 400000),
      _pair(10000, 400000),
      _pair(10000, 400000, busy: true),
      _pair(10000, 400000, busy: true),
      _pair(10000, 400000, busy: true),
    ], limit: 0.045);
    expect(result.clean, hasLength(2));
    expect(result.verdict, ShareVerdict.inconclusive);
    expect(result.describe('gate'), contains('INCONCLUSIVE'));
    expect(result.describe('gate'), contains('CONTENDED'));
  });

  test('the apart hold is judged too when a limit is given', () {
    final result = ShareResult(
      [
        // 230 / 600 = 0.383: under 0.6, but 230 ms over 220
        for (var i = 0; i < 3; i++) _pair(230000, 600000),
      ],
      limit: 0.6,
      apartMostUs: 220000,
    );
    expect(result.median, closeTo(0.383, 0.001));
    expect(result.apartMedianUs, 230000);
    expect(result.verdict, ShareVerdict.fail);
  });

  test('shareOf interleaves the pairs, and takes more only when the host '
      'was busy for half of them', () async {
    final order = <String>[];
    var n = 0;
    // Pairs 1-3 contended, then quiet.
    final quietRun = await shareOf(
      apart: () async {
        order.add('apart');
        return _held(10000, busy: n++ < 3);
      },
      whole: () async {
        order.add('whole');
        return _held(400000);
      },
      limit: 0.045,
    );
    expect(order.take(4), ['apart', 'whole', 'apart', 'whole']);
    // 3 of the first 5 contended: taken on to 9, 6 of them clean.
    expect(quietRun.pairs, hasLength(9));
    expect(quietRun.clean, hasLength(6));
    expect(quietRun.verdict, ShareVerdict.pass);

    // Clean and failing: no more pairs, no second chance.
    var taken = 0;
    final failing = await shareOf(
      apart: () async {
        taken++;
        return _held(30000);
      },
      whole: () async => _held(400000),
      limit: 0.045,
    );
    expect(taken, 5);
    expect(failing.verdict, ShareVerdict.fail);
  });

  test('shareOf keeps the figures of each run, never what it made', () async {
    final made = List.filled(100000, 0);
    final result = await shareOf(
      apart: () async => Held<Object?>(made, 10000, _quiet),
      whole: () async => Held<Object?>(made, 400000, _quiet),
      limit: 0.045,
    );
    expect(result.pairs, hasLength(5));
    for (final p in result.pairs) {
      expect(p.apart.result, isNull);
      expect(p.whole.result, isNull);
      expect(p.apart.heldUs, 10000);
      expect(p.whole.heldUs, 400000);
    }
  });

  test('an inconclusive gate fails under CI and is skipped loudly '
      'elsewhere', () {
    final contended = ShareResult([
      for (var i = 0; i < 9; i++) _pair(10000, 400000, busy: true),
    ], limit: 0.045);
    expect(
      () => expectShare(contended, 'gate', environment: const {'CI': 'true'}),
      throwsA(
        isA<TestFailure>().having(
          (f) => f.message,
          'message',
          contains('INCONCLUSIVE: host contended (0 of 9 samples clean)'),
        ),
      ),
    );
    final failing = ShareResult([
      for (var i = 0; i < 3; i++) _pair(30000, 400000),
    ], limit: 0.045);
    expect(
      () => expectShare(failing, 'gate', environment: const {}),
      throwsA(isA<TestFailure>()),
    );
    final passing = ShareResult([
      for (var i = 0; i < 3; i++) _pair(10000, 400000),
    ], limit: 0.045);
    expectShare(passing, 'gate', environment: const {});
  });

  test('leastOf runs every try and keeps the least', () async {
    final runs = [5, 2, 9];
    var i = 0;
    expect(await leastOf(3, () async => runs[i++]), 2);
    expect(i, 3);
    expect(gateTries, greaterThan(1));
  });

  test('this host has a witness', () {
    final reading = HostWitness.ofThisHost.read();
    expect(
      reading.psiSomeUs != null || reading.probeUs != null,
      isTrue,
      reason: 'PSI on Linux, the probe elsewhere',
    );
  });
}
