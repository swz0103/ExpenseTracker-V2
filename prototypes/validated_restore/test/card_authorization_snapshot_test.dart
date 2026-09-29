import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:backup_envelope_probe/envelope.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/card_authorizations_adapter.dart';
import 'package:modular_persistence_probe/card_statements_adapter.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/fixture_allocation.dart';
import 'package:modular_persistence_probe/storage_binding.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/snapshot.dart';
import 'package:validated_restore_probe/restore_store.dart';

void main() {
  final root = Directory('.dart_tool/card-authorization-snapshot-tests')
    ..createSync(recursive: true);
  final codec = SnapshotCodec(
    generationAware: true,
    correctionsAware: true,
    tombstonesAware: true,
    budgetsAware: true,
    recurringAware: true,
    creditCardsAware: true,
    cardStatementsAware: true,
    cardAuthorizationsAware: true,
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
    cardAuthorizationsAware: true,
  );

  OperationId operation() => OperationId(PublicId.generate());

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

  CardCharge charge() => CardCharge.pending(
    id: PublicId.generate(),
    workspace: fixture.ws,
    cardId: card.id,
    kind: CardChargeKind.purchase,
    authorizedOn: BusinessDate(2026, 9, 27),
    authorizedAmount: fixture.money('12.34'),
  );

  Future<void> createAllStates() async {
    await createCardAuthorization(source, charge(), operation());
    final cancelled = charge();
    await createCardAuthorization(source, cancelled, operation());
    await cancelCardAuthorization(
      source,
      fixture.ws,
      cancelled.id,
      operation(),
    );
    final posted = charge();
    await createCardAuthorization(source, posted, operation());
    final postOperation = operation();
    final event = Posting.expense(
      id: PublicId.generate(),
      operation: OperationKey(fixture.ws, postOperation),
      date: BusinessDate(2026, 9, 28),
      account: PostingAccount(
        id: card.id,
        workspace: fixture.ws,
        currency: card.currency,
        expectedVersion: 1,
      ),
      amount: fixture.money('12.39'),
    );
    await source.transaction(() async {
      await FinancialWorkflows(source).post(event);
      await registerPostedCardCharge(source, fixture.ws, event.id, card.id);
      await postCardAuthorization(
        source,
        workspace: fixture.ws,
        chargeId: posted.id,
        operation: postOperation,
        eventId: event.id,
        postedOn: event.date,
        settledAmount: fixture.money('12.34'),
        fee: fixture.money('0.05'),
      );
    });
  }

  test(
    'schema 19 pending, cancelled and posted facts restore exactly',
    () async {
      await createAllStates();
      final bytes = await codec.capture(source);
      final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(root['version'], 18);
      expect(root['schema'], 19);
      final tables = root['tables'] as Map<String, dynamic>;
      expect(tables['card_authorizations'], hasLength(3));
      expect(tables['card_authorization_resolutions'], hasLength(2));
      final cancelled = (tables['card_authorization_resolutions'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((row) => row['state'] == 'cancelled');
      expect(cancelled['event_id'], isNull);
      expect(cancelled['settled_minor'], isNull);

      final targetFile = File('${work.path}/restored.db');
      final binding = allocationBinding();
      await codec.stage(
        bytes,
        targetFile,
        openDatabase: (file) => database(file, binding),
      );
      final target = database(targetFile, binding);
      try {
        expect(await codec.capture(target), bytes);
        final restored = await cardAuthorizations(target, fixture.ws);
        expect(
          restored.map((fact) => fact.state).toSet(),
          CardAuthorizationState.values.toSet(),
        );
      } finally {
        await target.close();
      }
    },
  );

  test('schema 19 restore store accepts a matching opt-in codec', () async {
    await createAllStates();
    final backup = await EnvelopeCodec().create(
      await codec.capture(source),
      password: 'synthetic-only-password-2026',
    );
    final binding = allocationBinding();
    final store = RestoreStore(
      Directory('${work.path}/restore-store'),
      snapshot: codec,
      openDatabase: (file) => database(file, binding),
    );
    await store.restore(
      backup.envelope,
      password: 'synthetic-only-password-2026',
    );
    final target = database(store.current, binding);
    try {
      expect(await codec.capture(target), await codec.capture(source));
    } finally {
      await target.close();
    }
  });

  test(
    'tampered posting and omitted authorization facts are rejected',
    () async {
      await createAllStates();
      final bytes = await codec.capture(source);
      final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final tables = root['tables'] as Map<String, dynamic>;
      final resolutions = (tables['card_authorization_resolutions'] as List)
          .cast<Map<String, dynamic>>();
      resolutions.singleWhere((row) => row['state'] == 'posted')['fee_minor'] =
          '4';
      await expectLater(
        codec.stage(
          utf8.encode(jsonEncode(root)),
          File('${work.path}/tampered.db'),
          openDatabase: (file) => database(file, allocationBinding()),
        ),
        throwsA(isA<InvalidSnapshot>()),
      );

      final omitted = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      (omitted['tables'] as Map<String, dynamic>).remove('card_authorizations');
      await expectLater(
        codec.stage(
          utf8.encode(jsonEncode(omitted)),
          File('${work.path}/omitted.db'),
          openDatabase: (file) => database(file, allocationBinding()),
        ),
        throwsA(isA<InvalidSnapshot>()),
      );

      await source.customStatement(
        'UPDATE card_authorization_resolutions SET fee_minor=4 '
        "WHERE state='posted'",
      );
      await expectLater(codec.capture(source), throwsA(isA<InvalidSnapshot>()));
    },
  );

  test(
    'schema 18 backup stages into schema 19 with empty authorizations',
    () async {
      await createAllStates();
      final root = jsonDecode(
        utf8.decode(await codec.capture(source)),
      ) as Map<String, dynamic>;
      root['version'] = 17;
      root['schema'] = 18;
      (root['modules'] as Map<String, dynamic>).remove('card_authorizations');
      final tables = root['tables'] as Map<String, dynamic>;
      tables.remove('card_authorizations');
      tables.remove('card_authorization_resolutions');
      final targetFile = File('${work.path}/upgraded.db');
      final binding = allocationBinding();
      await codec.stage(
        utf8.encode(jsonEncode(root)),
        targetFile,
        openDatabase: (file) => database(file, binding),
      );
      final target = database(targetFile, binding);
      try {
        expect(await cardAuthorizations(target, fixture.ws), isEmpty);
        final upgraded = jsonDecode(
          utf8.decode(await codec.capture(target)),
        ) as Map<String, dynamic>;
        expect(upgraded['schema'], 19);
        expect(
          (upgraded['tables'] as Map<String, dynamic>)['card_authorizations'],
          isEmpty,
        );
      } finally {
        await target.close();
      }
    },
  );

  test(
    'encrypted schema 19 snapshot restores with either credential',
    () async {
      await createAllStates();
      final bytes = await codec.capture(source);
      final envelope = await EnvelopeCodec().create(
        bytes,
        password: 'synthetic-only-password-2026',
      );
      final decrypted = [
        await EnvelopeCodec().openWithPassword(
          envelope.envelope,
          'synthetic-only-password-2026',
        ),
        await EnvelopeCodec().openWithRecovery(
          envelope.envelope,
          envelope.recoveryKey,
        ),
      ];
      for (var index = 0; index < decrypted.length; index++) {
        final binding = allocationBinding();
        final file = File('${work.path}/credential-$index.db');
        await codec.stage(
          decrypted[index],
          file,
          openDatabase: (file) => database(file, binding),
        );
        final target = database(file, binding);
        try {
          expect(await codec.capture(target), bytes);
        } finally {
          await target.close();
        }
      }
    },
  );

  test(
    'schema 19 is opt in and count limit covers authorization rows',
    () async {
      expect(
        () => SnapshotCodec(cardAuthorizationsAware: true),
        throwsArgumentError,
      );
      await createAllStates();
      final bytes = await codec.capture(source);
      final oldCodec = SnapshotCodec(
        generationAware: true,
        correctionsAware: true,
        tombstonesAware: true,
        budgetsAware: true,
        recurringAware: true,
        creditCardsAware: true,
        cardStatementsAware: true,
      );
      await expectLater(
        oldCodec.capture(source),
        throwsA(isA<InvalidSnapshot>()),
      );
      final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final tables = root['tables'] as Map<String, dynamic>;
      tables['card_authorizations'] = List.filled(
        SnapshotCodec.maxRows + 1,
        (tables['card_authorizations'] as List).first,
      );
      await expectLater(
        codec.stage(
          utf8.encode(jsonEncode(root)),
          File('${work.path}/too-many.db'),
          openDatabase: (file) => database(file, allocationBinding()),
        ),
        throwsA(isA<InvalidSnapshot>()),
      );
    },
  );
}
