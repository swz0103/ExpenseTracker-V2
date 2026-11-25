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
  test('a name id is the same for the same name and says nothing of it', () {
    // Python: uuid.uuid5(UUID('6f2b7c1e-3d4a-5b8c-9e0f-1a2b3c4d5e6f'), '飲食').
    expect(NameId.of('飲食').value, '96c2539e-3dd4-5a29-becf-9344600ca2a9');
    expect(NameId.of('飲食'), NameId.of('飲食'));
    expect(NameId.of('飲食').hashCode, NameId.of('飲食').hashCode);
    expect(NameId.of('飲食'), isNot(NameId.of('交通')));
    expect('${NameId.of('#家用')}', isNot(contains('家用')));
  });
}
