import 'package:foundation_values/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  const a = '019f13f5-53cb-7219-8a3e-4b569376f32b';
  const b = '019f13f5-53cb-7219-8a3e-4b569376f32c';
  test('UUID v7 canonicalization, version and variant validation', () {
    expect(PublicId.parse(a.toUpperCase()), PublicId.parse(a));
    for (final value in [
      '',
      a.replaceFirst('7219', '4219'),
      a.replaceFirst('8a3e', 'ca3e'),
      '$a\n',
      a.replaceAll('-', ''),
    ]) {
      expect(() => PublicId.parse(value), throwsFormatException);
    }
  });
  test('generated IDs round trip and sample contains no duplicate', () {
    final values = List.generate(500, (_) => PublicId.generate());
    expect(values.toSet().length, values.length);
    for (final id in values) {
      expect(PublicId.parse(id.value), id);
    }
  });
  test(
    'operation identity includes workspace and is distinct from workspace ID',
    () {
      final operation = OperationId.parse(a);
      final workspaceA = WorkspaceId.parse(a);
      final workspaceB = WorkspaceId.parse(b);
      expect(operation, isNot(workspaceA));
      expect(
        OperationKey(workspaceA, operation),
        OperationKey(WorkspaceId.parse(a), OperationId.parse(a)),
      );
      expect(
        OperationKey(workspaceA, operation),
        isNot(OperationKey(workspaceB, operation)),
      );
    },
  );
  test('business dates validate leap years rather than normalize overflow', () {
    for (final value in [
      '2000-02-29',
      '2024-02-29',
      '2026-09-26',
      '0001-01-01',
      '9999-12-31',
    ]) {
      expect(BusinessDate.parse(value).toString(), value);
    }
    for (final value in [
      '1900-02-29',
      '2026-02-29',
      '2026-04-31',
      '2026-13-01',
      '0000-01-01',
      '2026-01-00',
      '2026-9-26',
      '2026-09-26Z',
    ]) {
      expect(() => BusinessDate.parse(value), throwsFormatException);
    }
  });
  test('date ordering follows calendar and does not infer a timezone', () {
    final dates = [
      '2027-01-01',
      '2026-12-31',
      '2024-02-29',
    ].map(BusinessDate.parse).toList()..sort();
    expect(dates.map((date) => date.toString()), [
      '2024-02-29',
      '2026-12-31',
      '2027-01-01',
    ]);
    expect(BusinessDate.parse('2026-09-26'), BusinessDate(2026, 9, 26));
  });
  test('UTC instant retains microseconds and converts an explicit offset', () {
    final instant = UtcInstant(
      DateTime.parse('2026-09-26T01:02:03.123456+08:00'),
    );
    expect(instant.toString(), '2026-09-25T17:02:03.123456Z');
    expect(UtcInstant.parse(instant.toString()), instant);
    expect(instant.value.isUtc, isTrue);
  });
  test('strict instant parsing rejects normalized or ambiguous input', () {
    for (final value in [
      '2026-09-26',
      '2026-09-26T00:00:00',
      '2026-09-26T00:00:00+08:00',
      '2026-02-30T00:00:00Z',
      '2026-09-26T24:00:00Z',
      '2026-09-26T00:60:00Z',
      '2026-09-26T00:00:60Z',
      '2026-09-26T00:00:00.1234567Z',
    ]) {
      expect(() => UtcInstant.parse(value), throwsFormatException);
    }
  });
}
