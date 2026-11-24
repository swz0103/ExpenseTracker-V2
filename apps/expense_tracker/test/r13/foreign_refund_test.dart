import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/import_export/model/import_export.dart';
import 'package:expense_tracker/src/features/import_export/ui/import_page.dart' show importBookOf;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('imported refund of a foreign purchase', () {
    final ledger = demoLedger();
    ledger.accountCommands.addAccount(const Account('usd', '美元戶', AccountKind.bank, 1000000, currency: 'USD'));
    const text =
        '日期,類型,金額,帳戶,商家,台幣金額\n'
        '2026-09-01,支出,100,美元戶,Shop,3210\n'
        '2026-09-02,退款,100,美元戶,Shop,3210\n';
    final found = importCsv(importBookOf(ledger), text, fallback: 'bank');
    print(found.problems);
    for (final e in found.entries) print('${e.type} amt=${e.amount} home=${e.home} spending=${e.spending}');
    addImport(ledger.entryCommands, found);
    print(ledger.reportService.expense(2026, 9));
  });
}
