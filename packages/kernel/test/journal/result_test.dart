import 'package:kernel/kernel.dart';
import 'package:test/test.dart';

const id = IntentId('i');

/// Every refusal names its intent, so a caller can say which.
String said(JournalResult r) => switch (r) {
  Written(:final report) => 'written ${report.posted}',
  Unbalanced(:final residual) => 'unbalanced $residual',
  UnknownAccount(:final account) => 'unknown ${account.value}',
  CurrencyMismatch(:final got) => 'mismatch ${got.value}',
  UnknownIntentType(:final type) => 'kind ${type.value}',
  IntentNotFound() => 'not found',
  RuleRejected(:final code) => 'rejected $code',
  UnknownAmendment(:final slot) => 'slot $slot',
  UnkeepableQuantity(:final account) => 'unkeepable ${account.value}',
};

void main() {
  test('each result says what it is', () {
    const report = (posted: 2, postings: 4, stale: <IntentId>[]);
    expect(said(const Written(report)), 'written 2');
    expect(said(const Unbalanced(id, CurrencyCode('TWD'), 3)), 'unbalanced 3');
    expect(said(const UnknownAccount(id, AccountId('a'))), 'unknown a');
    expect(
      said(
        const CurrencyMismatch(
          id,
          AccountId('a'),
          CurrencyCode('USD'),
          CurrencyCode('TWD'),
        ),
      ),
      'mismatch TWD',
    );
    expect(said(const UnknownIntentType(id, IntentType('k'))), 'kind k');
    expect(said(const IntentNotFound(id)), 'not found');
    expect(said(const RuleRejected(id, 'c')), 'rejected c');
    expect(said(const UnknownAmendment(id, 's')), 'slot s');
    expect(
      said(UnkeepableQuantity(id, const AccountId('h'), BigInt.one)),
      'unkeepable h',
    );
    expect(const RuleRejected(id, 'c').detail, '');
    expect(const IntentNotFound(id).intent, id);
  });
}
