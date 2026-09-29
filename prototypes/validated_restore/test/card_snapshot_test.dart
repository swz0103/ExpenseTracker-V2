import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/card_revisions_adapter.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/fixture_allocation.dart';
import 'package:modular_persistence_probe/storage_binding.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/snapshot.dart';

void main() {
  final root = Directory('.dart_tool/card-snapshot-tests')
    ..createSync(recursive: true);
  final codec = SnapshotCodec(
    generationAware: true,
    correctionsAware: true,
    tombstonesAware: true,
    budgetsAware: true,
    recurringAware: true,
    creditCardsAware: true,
  );
  late Directory work;
  late ProbeDatabase source;
  late AllocationFixture fixture;
  late PublicId cardId;

  ProbeDatabase database(File file, StorageBinding binding) => ProbeDatabase(
    file,
    storageBinding: binding,
    categoryAware: true,
    correctionsAware: true,
    tombstonesAware: true,
    budgetsAware: true,
    recurringAware: true,
    creditCardsAware: true,
  );

  setUp(() async {
    work = root.createTempSync('case-');
    source = database(File('${work.path}/source.db'), allocationBinding());
    fixture = AllocationFixture(source);
    await fixture.initialize();
    cardId = PublicId.generate();
    final account = Account.open(
      id: cardId,
      workspace: fixture.ws,
      name: 'Synthetic card',
      kind: AccountKind.creditCard,
      currency: fixture.currency,
      openedOn: BusinessDate(2026, 9, 29),
    );
    await FinancialWorkflows(source).createAccount(
      account,
      Posting.opening(
        id: PublicId.generate(),
        operation: OperationKey(fixture.ws, OperationId(PublicId.generate())),
        date: account.openedOn,
        account: PostingAccount(
          id: cardId,
          workspace: fixture.ws,
          currency: fixture.currency,
          expectedVersion: 1,
        ),
        amount: Money(fixture.currency, BigInt.zero),
      ),
      cardTerms: CreditCardTerms(
        workspace: fixture.ws,
        cardId: cardId,
        currency: fixture.currency,
        closingDay: 30,
        dueDay: 15,
      ),
    );
  });
  tearDown(() async {
    await source.close();
    work.deleteSync(recursive: true);
  });

  test(
    'schema 17 card settings survive portable stage with new binding',
    () async {
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
        final restored = (await currentCardTerms(target, fixture.ws)).single;
        expect(restored.cardId, cardId);
        expect(restored.closingDay, 30);
        expect(await codec.capture(target), bytes);
      } finally {
        await target.close();
      }
    },
  );

  test('tampered card terms fail before stage or backup', () async {
    final bytes = await codec.capture(source);
    final tampered = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final tables = tampered['tables'] as Map<String, dynamic>;
    (tables['card_revisions'] as List).single['payload'] = '{}';
    await expectLater(
      codec.stage(
        utf8.encode(jsonEncode(tampered)),
        File('${work.path}/tampered.db'),
        openDatabase: (file) => database(file, allocationBinding()),
      ),
      throwsA(isA<InvalidSnapshot>()),
    );
    await source.customStatement('UPDATE card_revisions SET payload=?', ['{}']);
    await expectLater(codec.capture(source), throwsA(isA<InvalidSnapshot>()));
  });
}
