import 'dart:convert';

import 'package:budgets/budgets.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:reports/reports.dart';
import 'package:test/test.dart';

void main() {
  final codec = BudgetPlanCodec();
  final workspace = WorkspaceId(PublicId.generate());
  final accountA = PublicId.generate();
  final accountB = PublicId.generate();
  final tag = PublicId.generate();
  final plan = BudgetPlan(
    id: PublicId.generate(),
    workspace: workspace,
    month: ReportMonth(2028, 2),
    limit: Money.parse(Currency('TWD', 2), '1200.50'),
    version: 3,
    categoryId: PublicId.generate(),
    accountIds: {accountB, accountA},
    tagIds: {tag},
    warningPercent: 75,
  );

  test('canonical round trip retains every budget authority field', () {
    final encoded = codec.encode(plan);
    final restored = codec.decode(encoded);
    expect(restored.id, plan.id);
    expect(restored.workspace, plan.workspace);
    expect(restored.month.toString(), '2028-02');
    expect(restored.limit.toJson(), plan.limit.toJson());
    expect(restored.version, 3);
    expect(restored.categoryId, plan.categoryId);
    expect(restored.accountIds, {accountA, accountB});
    expect(restored.tagIds, {tag});
    expect(restored.warningPercent, 75);
    expect(restored.repeats, isFalse);
    final monthly = BudgetPlan(
      id: plan.id,
      workspace: workspace,
      month: ReportMonth(2028, 2),
      limit: plan.limit,
      repeats: true,
    );
    expect(codec.decode(codec.encode(monthly)).repeats, isTrue);
    expect(codec.encode(restored), encoded);
  });

  test('unknown or missing fields and future formats fail closed', () {
    final original = jsonDecode(codec.encode(plan)) as Map<String, dynamic>;
    for (final mutation in [
      {...original, 'format': BudgetPlanCodec.formatVersion + 1},
      {...original, 'repeats': 'yes'},
      {...original, 'unrecognized': true},
      {...original}..remove('warningPercent'),
      {...original, 'month': 13},
      {
        ...original,
        'limit': {...original['limit'] as Map, 'extra': 1},
      },
      {
        ...original,
        'accountIds': [accountA.value, accountA.value],
      },
      {
        ...original,
        'tagIds': [tag.value, 'invalid'],
      },
    ]) {
      expect(() => codec.decode(jsonEncode(mutation)), throwsFormatException);
    }
    expect(() => codec.decode('{'), throwsFormatException);
  });

  test('size and selection bounds reject pathological plans', () {
    final original = jsonDecode(codec.encode(plan)) as Map<String, dynamic>;
    expect(
      () => codec.decode(' ' * (BudgetPlanCodec.maxBytes + 1)),
      throwsFormatException,
    );
    List<String> ids(int count) =>
        [for (var i = 0; i < count; i++) PublicId.generate().value]..sort();
    // The most selections fit in the byte limit on both lists ...
    final full = jsonEncode({
      ...original,
      'accountIds': ids(BudgetPlanCodec.maxSelections),
      'tagIds': ids(BudgetPlanCodec.maxSelections),
    });
    expect(utf8.encode(full).length, lessThan(BudgetPlanCodec.maxBytes));
    expect(codec.decode(full).accountIds, hasLength(150));
    // ... so one more is refused by the selection bound, not by size.
    final over = jsonEncode({
      ...original,
      'accountIds': ids(BudgetPlanCodec.maxSelections + 1),
    });
    expect(utf8.encode(over).length, lessThan(BudgetPlanCodec.maxBytes));
    expect(() => codec.decode(over), throwsFormatException);
  });
}
