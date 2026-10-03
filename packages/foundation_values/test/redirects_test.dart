import 'package:foundation_values/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  final ids = List.generate(5, (_) => PublicId.generate());

  test('every redirect resolves to the live entry at its end', () {
    // 0 -> 1 -> 2 (live), 3 -> 2, 4 live.
    final canonical = resolveRedirects({
      ids[0]: ids[1],
      ids[1]: ids[2],
      ids[2]: null,
      ids[3]: ids[2],
      ids[4]: null,
    })!;
    expect([for (final id in ids) canonical[id]], [
      ids[2],
      ids[2],
      ids[2],
      ids[2],
      ids[4],
    ]);
  });

  test('a long history resolves without recursion', () {
    final chain = List.generate(100000, (_) => PublicId.generate());
    final canonical = resolveRedirects({
      for (var i = 0; i < chain.length; i++)
        chain[i]: i + 1 < chain.length ? chain[i + 1] : null,
    })!;
    expect(canonical[chain.first], chain.last);
  });

  test('a cycle has no answer', () {
    expect(resolveRedirects({ids[0]: ids[1], ids[1]: ids[0]}), isNull);
    expect(resolveRedirects({ids[0]: ids[0]}), isNull);
  });
}
