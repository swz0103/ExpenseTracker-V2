import 'dart:convert';

import 'package:foundation_values/foundation_values.dart';
import 'package:recurring_transactions/recurring_transactions.dart';
import 'package:test/test.dart';

void main() {
  final template = RecurringTemplate(
    id: PublicId.parse('018f4a28-8080-7a10-8a10-123456789abc'),
    workspace: WorkspaceId.parse('018f4a28-8080-7a10-8a10-123456789abd'),
    accountId: PublicId.parse('018f4a28-8080-7a10-8a10-123456789abe'),
    label: '房租',
    amount: Money(Currency('TWD', 0), BigInt.from(-10000)),
    firstDate: BusinessDate.parse('2024-01-31'),
    unit: RecurrenceUnit.month,
    every: 2,
    version: 3,
  );
  final codec = RecurringTemplateCodec();

  test('canonical round trip preserves money, IDs and schedule', () {
    final encoded = codec.encode(template);
    final decoded = codec.decode(encoded);
    expect(codec.encode(decoded), encoded);
    expect(decoded.amount.minorUnits, BigInt.from(-10000));
    expect(decoded.accountId, template.accountId);
    expect(decoded.firstDate, template.firstDate);
    expect(decoded.unit, RecurrenceUnit.month);
  });

  test('end date and default classification round trip', () {
    final tag = PublicId.generate();
    final insurance = RecurringTemplate(
      id: template.id,
      workspace: template.workspace,
      accountId: template.accountId,
      label: '保險',
      amount: template.amount,
      firstDate: template.firstDate,
      unit: RecurrenceUnit.year,
      every: 1,
      lastDate: BusinessDate(2029, 12, 31),
      categoryId: PublicId.generate(),
      tagIds: {tag},
      merchantId: PublicId.generate(),
    );
    final decoded = codec.decode(codec.encode(insurance));
    expect(decoded.lastDate, BusinessDate(2029, 12, 31));
    expect(decoded.categoryId, insurance.categoryId);
    expect(decoded.tagIds, {tag});
    expect(decoded.merchantId, insurance.merchantId);
    final due = dueCandidates(
      insurance,
      after: BusinessDate(2023, 12, 31),
      through: BusinessDate(2035, 1, 1),
    );
    expect(due.map((c) => c.dueDate.year), [
      2024,
      2025,
      2026,
      2027,
      2028,
      2029,
    ]);
    expect(isScheduledDate(insurance, BusinessDate(2030, 1, 31)), isFalse);
  });

  test('unknown, missing, reordered and duplicated keys are rejected', () {
    final value = codec.encode(template);
    final map = jsonDecode(value) as Map<String, dynamic>;
    expect(
      () => codec.decode(jsonEncode({...map, 'extra': true})),
      throwsFormatException,
    );
    final without = Map<String, dynamic>.from(map)..remove('accountId');
    expect(() => codec.decode(jsonEncode(without)), throwsFormatException);
    final reordered = <String, dynamic>{'version': map['version'], ...map};
    expect(() => codec.decode(jsonEncode(reordered)), throwsFormatException);
    expect(value, startsWith('{"format":2,'));
    expect(
      () => codec.decode(
        value.replaceFirst('"format":2,', '"format":2,"format":2,'),
      ),
      throwsFormatException,
    );
  });

  test('future format and changed amount scale are rejected', () {
    final map = jsonDecode(codec.encode(template)) as Map<String, dynamic>;
    expect(
      () => codec.decode(jsonEncode({...map, 'format': 3})),
      throwsFormatException,
    );
    final amount = Map<String, dynamic>.from(map['amount'] as Map)
      ..['scale'] = -1;
    expect(
      () => codec.decode(jsonEncode({...map, 'amount': amount})),
      throwsA(isA<MoneyException>()),
    );
  });

  test('oversize and invalid labels fail closed', () {
    expect(
      () => codec.decode(' ' * (RecurringTemplateCodec.maxBytes + 1)),
      throwsFormatException,
    );
    expect(
      () => RecurringTemplate(
        id: template.id,
        workspace: template.workspace,
        accountId: template.accountId,
        label: 'bad\nlabel',
        amount: template.amount,
        firstDate: template.firstDate,
        unit: template.unit,
        every: 1,
      ),
      throwsFormatException,
    );
  });
}
