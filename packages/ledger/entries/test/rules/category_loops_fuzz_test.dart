import 'dart:math';

import 'package:ledger_entries/rules.dart';
import 'package:test/test.dart';

/// Review 18: [namesOnLoops] and [topOf] against a brute force over
/// random parent maps of up to seven names: self-parents, loops of one
/// or more, tails running into loops and parents that are not names.
void main() {
  test('names on loops and the top of each name agree with a brute '
      'force', () {
    final random = Random(5);
    for (var i = 0; i < 20000; i++) {
      final n = 1 + random.nextInt(7);
      final names = [for (var k = 0; k < n; k++) String.fromCharCode(97 + k)];
      final parents = <String, String?>{
        for (final name in names)
          name: random.nextInt(4) == 0
              ? null
              : random.nextInt(5) == 0
              ? 'zz'
              : names[random.nextInt(n)],
      };
      String? parentOf(String name) => parents[name];

      // A name is on a loop when walking its parents comes back to it.
      bool reaches(String from, String to) {
        var at = parentOf(from);
        for (var steps = 0; at != null && steps <= n + 2; steps++) {
          if (at == to) return true;
          at = parentOf(at);
        }
        return false;
      }

      final looped = {
        for (final name in names)
          if (reaches(name, name)) name,
      };
      expect(namesOnLoops(parents), looped, reason: '$parents');
      for (final name in names) {
        final top = topOf(name, parentOf);
        if (looped.contains(name)) {
          // On a loop, the top is the loop's first name in order.
          final loop = [
            name,
            for (final other in looped)
              if (other != name && reaches(name, other)) other,
          ]..sort();
          expect(top, loop.first, reason: '$parents $name');
        }
        // The top of a top is itself.
        expect(topOf(top, parentOf), top, reason: '$parents $name $top');
      }
    }
  });
}
