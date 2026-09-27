import 'dart:io';

import 'package:categories/categories.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/fixture_allocation.dart';
import 'package:modular_persistence_probe/categories_adapter.dart';
import 'package:modular_persistence_probe/tags_adapter.dart';
import 'package:modular_persistence_probe/merchants_adapter.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('.dart_tool/metadata-identity-tests')
    ..createSync(recursive: true);
  for (final table in ['categories', 'tags', 'merchants']) {
    test(
      '$table history rejects duplicate current ID replacing another row in damaged schema',
      () async {
        final work = root.createTempSync('case-'),
            ws = WorkspaceId(PublicId.generate());
        final db = ProbeDatabase(
          File('${work.path}/db'),
          storageBinding: allocationBinding(),
          merchantsAware: true,
        );
        try {
          final a = PublicId.generate(), b = PublicId.generate();
          OperationKey op() =>
              OperationKey(ws, OperationId(PublicId.generate()));
          if (table == 'merchants') {
            await MerchantsAdapter(db)
                .mutate(op(), MerchantMutation.create(a, 'A'));
            await MerchantsAdapter(db)
                .mutate(op(), MerchantMutation.create(b, 'B'));
          } else if (table == 'tags') {
            await TagsAdapter(db).mutate(op(), TagMutation.create(a, 'A'));
            await TagsAdapter(db).mutate(op(), TagMutation.create(b, 'B'));
          } else {
            await CategoriesAdapter(db).mutate(
              op(),
              CategoryMutation.create(a, 'A', CategoryKind.income),
            );
            await CategoriesAdapter(db).mutate(
              op(),
              CategoryMutation.create(b, 'B', CategoryKind.income),
            );
          }
          await db.customStatement('PRAGMA foreign_keys=OFF');
          await db.customStatement(
            'CREATE TABLE broken AS SELECT * FROM $table WHERE id=?',
            [a.value],
          );
          await db.customStatement('INSERT INTO broken SELECT * FROM broken');
          await db.customStatement('DROP TABLE $table');
          await db.customStatement('ALTER TABLE broken RENAME TO $table');
          await expectLater(switch (table) {
            'tags' => validateTagHistory(db),
            'merchants' => validateMerchantHistory(db),
            _ => validateCategoryHistory(db),
          }, throwsException);
        } finally {
          await db.close();
          if (!work.resolveSymbolicLinksSync().startsWith(
            '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
          ))
            throw StateError('Unsafe cleanup');
          work.deleteSync(recursive: true);
        }
      },
    );
  }
}
