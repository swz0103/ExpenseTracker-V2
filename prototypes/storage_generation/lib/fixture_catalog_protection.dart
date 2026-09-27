import 'dart:io';

import 'package:foundation_values/foundation_values.dart';

import 'catalog_protection.dart';
import 'fixture_key_slots.dart';

/// INSECURE plaintext fixture key provider; never use with real financial data.
CatalogProtection fixtureCatalogProtection(
  FixtureKeySlots slots, {
  PublicId? identity,
}) {
  final id = identity ?? PublicId.parse('019f0000-0000-7000-8000-000000000099');
  return CatalogProtection(id, (exists) async {
    final file = File('${slots.directory.path}/${id.value}.key');
    if (!await file.exists()) {
      if (exists) throw StateError('Catalog key missing');
      await slots.create(id);
    }
    return slots.read(id);
  });
}
