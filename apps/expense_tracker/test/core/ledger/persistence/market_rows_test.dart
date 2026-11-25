import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:expense_tracker/src/core/ledger/persistence/market_rows.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart' show StoredRow;

void main() {
  // Kept whole from 400 days before 2026-11-25: 2025-10-21.
  final today = BusinessDate(2026, 11, 25);
  StoredRow day(String on, String body) =>
      StoredRow(0, marketShelf, 'day:$on', body);

  group('foldedMarket (PERF-4)', () {
    test('a month already one row on its first day is not read', () {
      final errors = <Object>[];
      // March 2025 is folded already; its row cannot even be read, so
      // reading it would be told.
      final folded = foldedMarket(
        [day('2025-03-01', 'not json')],
        today,
        report: errors.add,
      );
      expect(folded.changes, isEmpty);
      expect(folded.from, isEmpty);
      expect(errors, isEmpty);
    });

    test('the rows of a month folded are what it was worked out from', () {
      final folded = foldedMarket([
        day('2025-03-03', '{"rates":{"USD":30.1}}'),
        day('2025-03-04', '{"rates":{"USD":30.2}}'),
        day('2026-11-24', '{"rates":{"USD":32.0}}'),
      ], today);
      expect(folded.from, {
        'day:2025-03-03': '{"rates":{"USD":30.1}}',
        'day:2025-03-04': '{"rates":{"USD":30.2}}',
      });
      expect(folded.changes, hasLength(3));
    });
  });

  group('foldStillApplies (PERF-4)', () {
    final from = {
      'day:2025-03-03': '{"rates":{"USD":30.1}}',
      'day:2025-03-04': '{"rates":{"USD":30.2}}',
    };
    final kept = [
      day('2025-03-03', '{"rates":{"USD":30.1}}'),
      day('2025-03-04', '{"rates":{"USD":30.2}}'),
      // Another month's row, and the latest board: not weighed.
      day('2026-11-24', '{"rates":{"USD":32.0}}'),
      StoredRow(0, marketShelf, 'board', '{}'),
    ];

    test('applies to the rows it was worked out from', () {
      expect(foldStillApplies(from, kept), isTrue);
    });

    test('not when a day of the month was added', () {
      expect(
        foldStillApplies(from, [
          ...kept,
          day('2025-03-05', '{"rates":{"USD":30.3}}'),
        ]),
        isFalse,
      );
    });

    test('not when a day of the month was changed', () {
      expect(
        foldStillApplies(from, [
          day('2025-03-03', '{"rates":{"USD":30.1}}'),
          day('2025-03-04', '{"rates":{"USD":31.0}}'),
        ]),
        isFalse,
      );
    });

    test('not when a day of the month was taken away', () {
      expect(foldStillApplies(from, [kept.first]), isFalse);
    });
  });
}
