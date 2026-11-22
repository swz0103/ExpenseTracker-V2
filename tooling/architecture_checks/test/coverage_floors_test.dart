import 'package:architecture_checks/coverage_floors.dart';
import 'package:test/test.dart';

const _lcov = '''
TN:
SF:lib/a.dart
DA:1,1
DA:2,0
DA:3,5
DA:4,0
LF:4
LH:2
end_of_record
SF:lib/b.dart
DA:1,0
DA:2,2
end_of_record
''';

void main() {
  group('parseLcov', () {
    test('counts hit and instrumented lines over all files', () {
      final coverage = parseLcov(_lcov);
      expect(coverage.total, 6);
      expect(coverage.hit, 3);
      expect(coverage.percent, 50);
    });

    test('a line merged from two records counts once, hit if either hit', () {
      final coverage = parseLcov(
        'SF:lib/a.dart\nDA:1,0\nend_of_record\n'
        'SF:lib/a.dart\nDA:1,3\nDA:2,0\nend_of_record\n',
      );
      expect(coverage.total, 2);
      expect(coverage.hit, 1);
    });

    test('ignores branch, function and malformed records', () {
      final coverage = parseLcov(
        'SF:lib/a.dart\nFN:1,main\nFNDA:1,main\nBRDA:1,0,0,1\nDA:x,1\n'
        'DA:5\nDA:6,1\nend_of_record\n',
      );
      expect(coverage.total, 1);
      expect(coverage.hit, 1);
    });

    test('an empty report is fully covered, not a division by zero', () {
      expect(parseLcov('').percent, 100);
    });

    test('handles Windows line endings', () {
      expect(parseLcov('SF:a\r\nDA:1,1\r\nDA:2,0\r\nend_of_record\r\n').hit, 1);
    });
  });

  group('checkFloors', () {
    test('passes at or above the floor', () {
      final results = checkFloors({'a': 80, 'b': 80}, {'a': 80.0, 'b': 81.5});
      expect(results.where((r) => r.failed), isEmpty);
    });

    test('fails below the floor', () {
      final result = checkFloors({'a': 80}, {'a': 79.9}).single;
      expect(result.belowFloor, isTrue);
      expect(result.toString(), contains('below the floor of 80%'));
    });

    test('fails when the package has no report', () {
      final result = checkFloors({'a': 80}, {'a': null}).single;
      expect(result.failed, isTrue);
      expect(result.toString(), contains('no coverage report'));
    });

    test('hints to raise the floor from 3 points above it', () {
      expect(checkFloors({'a': 80}, {'a': 82.9}).single.raiseHint, isFalse);
      final high = checkFloors({'a': 80}, {'a': 83.0}).single;
      expect(high.raiseHint, isTrue);
      expect(high.failed, isFalse);
      expect(high.toString(), contains('raise the floor'));
    });
  });
}
