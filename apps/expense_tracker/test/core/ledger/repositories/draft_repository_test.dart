import 'package:expense_tracker/src/core/ledger/repositories/draft_repository.dart';
import 'package:expense_tracker/src/core/diagnostics/error_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a tab with nothing put aside has no form', () {
    expect(DraftRepository().of('expense'), isNull);
  });

  test('a form put aside is told as a change, the same one again is not', () {
    final drafts = DraftRepository();
    expect(drafts.set('expense', '{"amount":1}'), isTrue);
    expect(drafts.set('expense', '{"amount":1}'), isFalse);
    expect(drafts.of('expense'), '{"amount":1}');
  });

  test('a form cleared is gone; clearing none changes nothing', () {
    final drafts = DraftRepository({'expense': '{}'});
    expect(drafts.set('expense', null), isTrue);
    expect(drafts.of('expense'), isNull);
    expect(drafts.set('expense', null), isFalse);
  });

  test('the photos the forms chose are listed, unreadable forms skipped', () {
    final drafts = DraftRepository({
      'expense': '{"receipt":"a.jpg"}',
      'income': '{"amount":5}',
      'transfer': '{"receipt":7}',
      'buy': 'not json',
      'sell': '[1, 2]',
    });
    expect(drafts.receipts.toList(), ['a.jpg']);
  });

  test('a form that cannot be read is kept in the error log, not passed '
      'over unseen', () {
    final before = ErrorLog.instance.count;
    final drafts = DraftRepository({'buy': 'not json'});
    expect(drafts.receipts.toList(), isEmpty);
    expect(ErrorLog.instance.count, before + 1);
    expect(
      ErrorLog.instance.entries.first.$2,
      startsWith('暫存的表單：FormatException'),
    );
  });

  test('another read anew is taken whole', () {
    final drafts = DraftRepository({'expense': '{}'});
    drafts.replaceWith(DraftRepository({'income': '{}'}));
    expect(drafts.of('expense'), isNull);
    expect(drafts.of('income'), '{}');
  });
}
