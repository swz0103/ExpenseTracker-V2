import 'package:expense_tracker/src/core/text/json_fields.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final json = JsonFields.decode(
    '{"on":true,"n":3,"f":3.0,"half":2.5,"s":"a","list":["a",1,"b"],'
    '"obj":{"x":1},"objs":[{"x":1},2],"wrong":"7"}',
  );

  test('each field as its type, null when missing or of another', () {
    expect(json.flag('on'), isTrue);
    expect(json.flag('s'), isNull);
    expect(json.whole('n'), 3);
    expect(json.whole('f'), 3);
    expect(json.whole('half'), isNull);
    expect(json.whole('wrong'), isNull);
    expect(json.text('s'), 'a');
    expect(json.text('n'), isNull);
    expect(json.text('missing'), isNull);
    expect(json.texts('list'), ['a', 'b']);
    expect(json.texts('s'), isNull);
    expect(json.object('obj')?.whole('x'), 1);
    expect(json.objects('objs'), hasLength(1));
  });

  test('a field that must be there names itself when it is not', () {
    expect(json.need<String>('s'), 'a');
    expect(
      () => json.need<String>('n'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          'n: expected String, found int',
        ),
      ),
    );
    expect(
      () => json.need<int>('missing'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          'missing: expected int, found nothing',
        ),
      ),
    );
  });

  test('only an object is one', () {
    expect(() => JsonFields.decode('[1]'), throwsA(isA<FormatException>()));
    expect(() => JsonFields.decode('{'), throwsA(isA<FormatException>()));
    expect(() => JsonFields.of(null), throwsA(isA<FormatException>()));
  });
}
