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
  test('a name id is the same for the same name and salt, says nothing of '
      'it, and is another under another salt', () {
    final salt = NameSalt.parse('6F2B7C1E-3D4A-4B8C-9E0F-1A2B3C4D5E6F');
    // Python: uuid.uuid5(UUID('6f2b7c1e-3d4a-4b8c-9e0f-1a2b3c4d5e6f'), '飲食').
    expect(NameId.of('飲食', salt).value, '68cafcdf-6930-5659-9679-98eb649ca6f3');
    expect(NameId.of('飲食', salt), NameId.of('飲食', salt));
    expect(NameId.of('飲食', salt).hashCode, NameId.of('飲食', salt).hashCode);
    expect(NameId.of('飲食', salt), isNot(NameId.of('交通', salt)));
    expect('${NameId.of('#家用', salt)}', isNot(contains('家用')));
    final other = NameSalt.parse('0b8e2f6a-91c4-4d3e-a7f5-2c6d8e0a1b3c');
    expect(NameId.of('飲食', other), isNot(NameId.of('飲食', salt)));
  });
  test('a salt is a version 4 UUID, new each time, and never shown', () {
    final made = List.generate(200, (_) => NameSalt.generate());
    expect(made.toSet().length, made.length);
    for (final salt in made) {
      expect(NameSalt.parse(salt.value), salt);
      expect(salt.hashCode, NameSalt.parse(salt.value).hashCode);
      expect('$salt', isNot(contains(salt.value)));
    }
    for (final value in [
      '',
      // Version 5, and a version 4 of the wrong variant.
      '6f2b7c1e-3d4a-5b8c-9e0f-1a2b3c4d5e6f',
      '6f2b7c1e-3d4a-4b8c-1e0f-1a2b3c4d5e6f',
    ]) {
      expect(() => NameSalt.parse(value), throwsFormatException);
      expect(NameSalt.tryParse(value), isNull);
    }
    expect(
      NameSalt.tryParse('0B8E2F6A-91C4-4D3E-A7F5-2C6D8E0A1B3C')?.value,
      '0b8e2f6a-91c4-4d3e-a7f5-2c6d8e0a1b3c',
    );
  });
}
