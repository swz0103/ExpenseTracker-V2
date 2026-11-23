import 'package:kernel/kernel.dart';
import 'package:test/test.dart';

import '../support/book.dart';

void main() {
  test('which classes are on the balance sheet, which are flows', () {
    expect(
      [for (final c in AccountClass.values) c.isBalanceSheet],
      [true, true, false, false, false],
    );
    expect(
      [for (final c in AccountClass.values) c.isFlow],
      [false, false, false, true, true],
    );
  });

  test('an account counts everywhere unless it says not', () {
    const a = LedgerAccount(
      id: bank,
      cls: AccountClass.asset,
      name: 'bank',
      owner: owner,
    );
    expect((a.inNetWorth, a.inFlowReports, a.tag), (true, true, ''));
    expect((a.currency, a.commodity, a.parent), (null, null, null));
  });

  test('the tree finds accounts by id, class, tag and owner', () {
    final t = tree();
    expect(t[bank]!.name, 'bank');
    expect(t[const AccountId('none')], isNull);
    expect(
      [for (final a in t.where(cls: AccountClass.asset)) a.id],
      [bank, cash, dollars, jar],
    );
    expect(t.where(tag: 'x'), isEmpty);
    expect(t.where(owner: const OwnerId('other')), isEmpty);
    expect(t.all.length, 6);
    t.put(
      const LedgerAccount(
        id: bank,
        cls: AccountClass.asset,
        name: 'renamed',
        owner: owner,
        tag: 'x',
      ),
    );
    expect(t[bank]!.name, 'renamed');
    expect([for (final a in t.where(tag: 'x')) a.id], [bank]);
  });

  test('two accounts of the same values are equal', () {
    LedgerAccount a(String name) => LedgerAccount(
      id: food,
      cls: AccountClass.expense,
      name: name,
      owner: owner,
      inFlowReports: false,
    );
    expect(a('x'), a('x'));
    expect(a('x').hashCode, a('x').hashCode);
    expect(a('x'), isNot(a('y')));
  });
}
