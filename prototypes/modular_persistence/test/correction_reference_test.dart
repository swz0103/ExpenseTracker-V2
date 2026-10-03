import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/fixture_allocation.dart'
    show allocationBinding;
import 'package:modular_persistence_probe/merchant_reference_validation.dart';
import 'package:modular_persistence_probe/merchants_adapter.dart';
import 'package:modular_persistence_probe/tag_reference_validation.dart';
import 'package:modular_persistence_probe/tags_adapter.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:test/test.dart';

/// Regression for G7-02: correcting a tagged or merchant-linked entry wraps
/// both leg receipts in `correction-event-v1`. The reference validators must
/// read the inner posting, or every later backup capture fails.
void main() {
  final root = Directory('.dart_tool/correction-reference-tests')
    ..createSync(recursive: true);
  final workspace = WorkspaceId(PublicId.generate());
  final currency = Currency('USD', 2);
  final date = BusinessDate(2026, 9, 28);
  late Directory work;
  late ProbeDatabase db;
  late FinancialWorkflows flows;
  late Account account;

  OperationKey op() =>
      OperationKey(workspace, OperationId(PublicId.generate()));
  Money money(String amount) => Money.parse(currency, amount);
  PostingAccount ref(Account a) => PostingAccount(
    id: a.id,
    workspace: a.workspace,
    currency: a.currency,
    expectedVersion: a.version,
  );

  setUp(() async {
    work = root.createTempSync('case-');
    db = ProbeDatabase(
      File('${work.path}/finance.db'),
      storageBinding: allocationBinding(),
      correctionsAware: true,
    );
    flows = FinancialWorkflows(db);
    account = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'synthetic',
      kind: AccountKind.bank,
      currency: currency,
      openedOn: date,
    );
    await flows.createAccount(
      account,
      Posting.opening(
        id: PublicId.generate(),
        operation: op(),
        date: date,
        account: ref(account),
        amount: money('100'),
      ),
    );
  });
  tearDown(() async {
    await db.close();
    if (!work.resolveSymbolicLinksSync().startsWith(
      '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
    )) {
      throw StateError('Unsafe cleanup');
    }
    work.deleteSync(recursive: true);
  });

  test('corrected tagged and merchant-linked entry keeps references valid',
      () async {
    final tag = PublicId.generate(), merchant = PublicId.generate();
    await TagsAdapter(db).mutate(op(), TagMutation.create(tag, 'Trip'));
    await MerchantsAdapter(db)
        .mutate(op(), MerchantMutation.create(merchant, 'Cafe'));
    final original = Posting.expense(
      id: PublicId.generate(),
      operation: op(),
      date: date,
      account: ref(account),
      amount: money('10'),
    );
    await flows.post(
      original,
      tags: [TagSelection(tag, 1)],
      merchant: MerchantSelection(merchant, 1),
    );
    await validateTagReferences(db);
    await validateMerchantReferences(db);

    await flows.correct(
      PostingCorrection(
        original: original,
        replacement: Posting.expense(
          id: PublicId.generate(),
          operation: op(),
          date: date,
          account: ref(account),
          amount: money('7'),
        ),
        reversalId: PublicId.generate(),
        reversalOperation: op(),
        reason: 'incorrect amount',
      ),
      replacementTags: [TagSelection(tag, 1)],
      replacementMerchant: MerchantSelection(merchant, 1),
    );

    await validateTagReferences(db);
    await validateMerchantReferences(db);
    expect(await flows.ledger.balance(ref(account)), money('93'));
  });
}
