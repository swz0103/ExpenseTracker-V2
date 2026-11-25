import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_bench.dart';

// The shape bench_test.dart writes to build/integration_response_data.json.
const _sample = <String, dynamic>{
  'entries': 3600,
  'load_ms': 15,
  'memory_mb': 232,
  'save': {'average_frame_build_time_millis': 1.8, 'frame_count': 12},
};

void main() {
  test('figures within their limits pass', () {
    final findings = checkBench(_sample, {
      'load_ms': 30,
      'memory_mb': 470,
      'save.average_frame_build_time_millis': 4,
    });
    expect(findings.where((f) => f.failed), isEmpty);
  });

  test('a figure above its limit fails and is named', () {
    final findings = checkBench(_sample, {'load_ms': 10});
    expect(findings.single.exceeded, isTrue);
    expect(findings.single.toString(), 'load_ms: 15 > 10');
  });

  test('a figure equal to its limit passes', () {
    expect(checkBench(_sample, {'load_ms': 15}).single.failed, isFalse);
  });

  test('a missing figure fails instead of passing silently', () {
    final findings = checkBench(_sample, {
      '100k_load_ms': 1700,
      'save.nothing': 1,
    });
    expect(findings.every((f) => f.missing && f.failed), isTrue);
  });

  test('dotted keys only descend into nested maps', () {
    expect(readFigure(_sample, 'save.frame_count'), 12);
    expect(readFigure(_sample, 'load_ms.deeper'), isNull);
  });

  test('the committed thresholds are all positive numbers', () {
    final limits = jsonDecode(
      File('test/perf/thresholds.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(limits, isNotEmpty);
    for (final entry in limits.entries) {
      expect(entry.value, isA<num>(), reason: entry.key);
      expect(entry.value as num, greaterThan(0), reason: entry.key);
    }
  });

  test('the first-open journal rebuild at 100k is gated, time and hold', () {
    final limits = jsonDecode(
      File('test/perf/thresholds.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    // Written by integration_test/bench_test.dart as `key('journal_...')`.
    expect(limits, contains('100k_journal_rebuild_ms'));
    expect(limits, contains('100k_journal_rebuild_held_ms'));
  });
}
