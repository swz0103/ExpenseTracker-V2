import 'package:core/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  const a = '019f13f5-53cb-7219-8a3e-4b569376f32b';
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
}
