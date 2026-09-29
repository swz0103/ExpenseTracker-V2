import 'dart:io';

import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/fixture_allocation.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/snapshot.dart';

void main() {
  final root = Directory('.dart_tool/investment-sale-guard-tests')
    ..createSync(recursive: true);

  test('schema 22 tables cannot be exported by a schema 21 codec', () async {
    final work = root.createTempSync('case-');
    final db = ProbeDatabase(
      File('${work.path}/finance.db'),
      storageBinding: allocationBinding(),
      categoryAware: true,
      correctionsAware: true,
      tombstonesAware: true,
      budgetsAware: true,
      recurringAware: true,
      creditCardsAware: true,
      cardStatementsAware: true,
      cardAuthorizationsAware: true,
      installmentsAware: true,
      investmentsAware: true,
      investmentSalesAware: true,
    );
    try {
      expect(db.schemaVersion, 22);
      final names = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name IN ('investment_sales','investment_sale_allocations')",
          )
          .get();
      expect(names.map((row) => row.read<String>('name')).toSet(), {
        'investment_sales',
        'investment_sale_allocations',
      });
      final oldCodec = SnapshotCodec(
        generationAware: true,
        correctionsAware: true,
        tombstonesAware: true,
        budgetsAware: true,
        recurringAware: true,
        creditCardsAware: true,
        cardStatementsAware: true,
        cardAuthorizationsAware: true,
        installmentsAware: true,
        investmentsAware: true,
      );
      await expectLater(oldCodec.validate(db), throwsA(isA<InvalidSnapshot>()));
      await expectLater(oldCodec.capture(db), throwsA(isA<InvalidSnapshot>()));
    } finally {
      await db.close();
      await work.delete(recursive: true);
    }
  });
}
