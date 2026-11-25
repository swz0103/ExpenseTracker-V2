import 'package:kernel/kernel.dart';
import 'package:test/test.dart';

const words = ContributionPoint<String>('words');
const numbers = ContributionPoint<int>('numbers');

void main() {
  test('what owners add, in order, with who added it', () {
    final c = Contributions();
    c.on(words)
      ..add(const OwnerId('a'), 'one')
      ..add(const OwnerId('b'), 'two');
    c.on(numbers).add(const OwnerId('a'), 3);
    expect(c.of(words), ['one', 'two']);
    expect(c.owned(words), [
      (const OwnerId('a'), 'one'),
      (const OwnerId('b'), 'two'),
    ]);
    expect(c.of(numbers), [3]);
    expect(c.of(valuers), isEmpty);
    expect(c.owned(valuers), isEmpty);
    expect(words.name, 'words');
  });
}
