import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/card_statements_adapter.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/fixture_allocation.dart';
import 'package:modular_persistence_probe/storage_binding.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/snapshot.dart';

void main() {
  final root = Directory('.dart_tool/card-statement-snapshot-tests')
    ..createSync(recursive: true);
  final codec = SnapshotCodec(
    generationAware: true,
    correctionsAware: true,
    tombstonesAware: true,
    budgetsAware: true,
    recurringAware: true,
    creditCardsAware: true,
    cardStatementsAware: true,
  );
  late Directory work;
  late ProbeDatabase source;
  late AllocationFixture fixture;
  late Account card;

  ProbeDatabase database(File file, StorageBinding binding) => ProbeDatabase(
    file,
    storageBinding: binding,
    categoryAware: true,
    correctionsAware: true,
    tombstonesAware: true,
    budgetsAware: true,
    recurringAware: true,
    creditCardsAware: true,
    cardStatementsAware: true,
  );

  setUp(() async {
    work = root.createTempSync('case-');
    source = database(File('${work.path}/source.db'), allocationBinding());
    fixture = AllocationFixture(source);
    await fixture.initialize();
    card = Account.open(
      id: PublicId.generate(),
      workspace: fixture.ws,
      name: 'Synthetic card',
      kind: AccountKind.creditCard,
      currency: fixture.currency,
      openedOn: BusinessDate(2026, 1, 1),
    );
    await FinancialWorkflows(source).createAccount(
      card,
      Posting.opening(
        id: PublicId.generate(),
        operation: fixture.operation(),
        date: card.openedOn,
        account: PostingAccount(
          id: card.id,
          workspace: fixture.ws,
          currency: card.currency,
          expectedVersion: 1,
        ),
        amount: Money(card.currency, BigInt.zero),
      ),
      cardTerms: CreditCardTerms(
        workspace: fixture.ws,
        cardId: card.id,
        currency: card.currency,
        closingDay: 28,
        dueDay: 15,
      ),
    );
  });

  tearDown(() async {
    await source.close();
    work.deleteSync(recursive: true);
  });

  Future<void> chargeAndConfirm() async {
    final charge = Posting.expense(
      id: PublicId.generate(),
      operation: fixture.operation(),
      date: BusinessDate(2026, 9, 27),
      account: PostingAccount(
        id: card.id,
        workspace: fixture.ws,
        currency: card.currency,
        expectedVersion: 1,
      ),
      amount: fixture.money('12.34'),
    );
    await source.transaction(() async {
      await FinancialWorkflows(source).post(charge);
      await registerPostedCardCharge(source, fixture.ws, charge.id, card.id);
    });
    await appendCardStatementRevision(
      source,
      workspace: fixture.ws,
      statementId: PublicId.generate(),
      cardId: card.id,
      revision: 1,
      cycle: CardCycle(
        startsAfter: BusinessDate(2026, 8, 28),
        closesOn: BusinessDate(2026, 9, 29),
        dueOn: BusinessDate(2026, 10, 15),
      ),
      billed: fixture.money('12.34'),
      operation: OperationId(PublicId.generate()),
    );
  }

  test(
    'schema 18 charge and confirmed dates survive portable restore',
    () async {
      await chargeAndConfirm();
      final bytes = await codec.capture(source);
      final targetFile = File('${work.path}/target.db');
      final binding = allocationBinding();
      await codec.stage(
        bytes,
        targetFile,
        openDatabase: (file) => database(file, binding),
      );
      final target = database(targetFile, binding);
      try {
        expect(await codec.capture(target), bytes);
      } finally {
        await target.close();
      }
    },
  );

  test('changed charge amount cannot be staged or backed up', () async {
    await chargeAndConfirm();
    final bytes = await codec.capture(source);
    final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final tables = root['tables'] as Map<String, dynamic>;
    (tables['card_posted_charges'] as List).single['amount_minor'] = '999';
    await expectLater(
      codec.stage(
        utf8.encode(jsonEncode(root)),
        File('${work.path}/tampered.db'),
        openDatabase: (file) => database(file, allocationBinding()),
      ),
      throwsA(isA<InvalidSnapshot>()),
    );
    await source.customStatement(
      'UPDATE card_posted_charges SET amount_minor=999',
    );
    await expectLater(codec.capture(source), throwsA(isA<InvalidSnapshot>()));
  });
}
