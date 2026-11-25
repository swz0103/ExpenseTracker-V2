import 'dart:convert';
import 'dart:io';

import 'package:expense_tracker/src/core/ledger/journal/old_shapes.dart';
import 'package:expense_tracker/src/core/ledger/journal/parity.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/codec/category_refs.dart';
import 'package:expense_tracker/src/core/ledger/persistence/codec/record_json.dart';
import 'package:expense_tracker/src/core/ledger/persistence/record_version.dart';
import 'package:flutter_test/flutter_test.dart';

import 'awkward_book.dart';
import '../../../core/ledger/journal/posted_book.dart';

void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('awkward-'));
  tearDown(() => scratch.deleteSync(recursive: true));

  test('writes the kept book', () {
    final categories = awkwardCategories();
    final refs = CategoryRefs(categories);
    String row(Map<String, Object?> json) =>
        jsonEncode({...json, '_v': recordVersion});
    File(keptFile).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'account': [for (final a in awkwardAccounts) row(accountToJson(a))],
        'category': [for (final c in categories) row(categoryToJson(c, refs))],
        'entry': [
          for (final e in [...fitting, ...oldShapes]) row(entryToJson(e, refs)),
        ],
      }),
    );
  }, skip: Platform.environment['MAKE_FIXTURES'] == null);

  test('the kept book of awkward shapes: every figure from its postings, '
      'each old shape counted', () async {
    final ledger = await openKept(scratch);
    expect(ledger.entries.all.length, fitting.length + oldShapes.length);
    expectGoldenPostings('awkward', await post(ledger));
    final parity = await parityOf(ledger);
    // ignore: avoid_print
    print('awkward: ${parity.figures} figures; shapes ${parity.shapes}');
    expect(parity, isA<InParity>(), reason: _said(parity));
    expect(parity.shapes, {for (final shape in OldShape.values) shape: 1});
  });

  test('the shapes that fit need no old shape', () async {
    final ledger = Ledger(
      today: day(10, 4),
      accounts: awkwardAccounts,
      categories: awkwardCategories(),
      entries: fitting,
      holdings: const [],
      budgets: const [],
      recurring: const [],
    );
    final parity = await parityOf(ledger);
    expect(parity, isA<InParity>(), reason: _said(parity));
    expect(parity.shapes, isEmpty);
  });
}

String _said(Parity p) => switch (p) {
  InParity() => '',
  OutOfParity(:final differences) => differences.take(30).join('\n'),
};
