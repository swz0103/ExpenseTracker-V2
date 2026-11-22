// E-invoice import: the ministry's consumption CSV and the M and D lines.
// Voided invoices are left out and an invoice's items add up to its total.
import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:domain/data_exchange.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/import_export/model/import_export.dart';
import 'package:expense_tracker/src/features/import_export/ui/import_page.dart'
    show importBookOf;
import 'package:flutter_test/flutter_test.dart';

import 'baseline_ledger.dart';

const head = '發票日期,發票號碼,賣方名稱,發票狀態,消費明細_品名,消費明細_金額\n';

Ledger book() => ledgerOf(
  today: day(2026, 10, 10),
  accounts: const [
    Account('bank', '銀行', AccountKind.bank, 0),
    Account('usd', '美元', AccountKind.bank, 0, currency: 'USD'),
  ],
  categories: [
    Category('交通通勤', 'car', 0xFF5C9A83),
    Category('飲食日常', 'food', 0xFF5B8DB0),
  ],
);

Import invoices(Ledger ledger, String text, {String account = 'bank'}) =>
    importInvoices(importBookOf(ledger), text, account: account);

void main() {
  group('the ministry CSV, read by the domain package', () {
    test('items add up to the invoice total', () {
      final found = parseEInvoices(
        '$head'
        '20261003,CD00000001,全聯福利中心,開立,鮮奶,199\n'
        '20261003,CD00000001,全聯福利中心,開立,吐司,69\n',
      );
      expect(found, hasLength(1));
      // 199 + 69 = 268.
      expect(found.single.amount.minorUnits, BigInt.from(268));
      expect(found.single.items, ['鮮奶', '吐司']);
      expect(found.single.seller, '全聯福利中心');
      expect(found.single.date, BusinessDate(2026, 10, 3));
    });
    test('a voided invoice is left out, all of its rows', () {
      final found = parseEInvoices(
        '$head'
        '20261003,CD00000001,甲店,開立,鮮奶,199\n'
        '20261004,CD00000002,乙店,作廢,飲料,50\n'
        '20261004,CD00000002,乙店,作廢,餅乾,30\n',
      );
      expect(found.map((i) => i.number), ['CD00000001']);
    });
    test('the same item twice is counted twice but listed once', () {
      final found = parseEInvoices(
        '$head'
        '20261003,CD00000001,甲店,開立,鮮奶,199\n'
        '20261003,CD00000001,甲店,開立,鮮奶,199\n',
      );
      // 199 + 199 = 398.
      expect(found.single.amount.minorUnits, BigInt.from(398));
      expect(found.single.items, ['鮮奶']);
    });
    test('a discount line takes its amount off', () {
      final found = parseEInvoices(
        '$head'
        '20261003,CD00000001,甲店,開立,鮮奶,199\n'
        '20261003,CD00000001,甲店,開立,折扣,-30\n',
      );
      // 199 - 30 = 169.
      expect(found.single.amount.minorUnits, BigInt.from(169));
    });
    test('decimal item amounts are added exactly, then rounded', () {
      final found = parseEInvoices(
        '$head'
        '20261003,CD00000001,甲店,開立,甲,10.4\n'
        '20261003,CD00000001,甲店,開立,乙,10.4\n'
        '20261003,CD00000002,甲店,開立,甲,10.5\n'
        '20261003,CD00000002,甲店,開立,乙,10.5\n',
      );
      // 10.4 + 10.4 = 20.8 -> 21 (a float would give 20.8000000000000007).
      expect(found[0].amount.minorUnits, BigInt.from(21));
      // 10.5 + 10.5 = 21 exactly.
      expect(found[1].amount.minorUnits, BigInt.from(21));
    });
    test('columns are found by name, in any order', () {
      final found = parseEInvoices(
        '消費明細_金額,賣方名稱,發票號碼,發票日期\n'
        '120,甲店,CD00000001,20261003\n',
      );
      expect(found.single.amount.minorUnits, BigInt.from(120));
      expect(found.single.number, 'CD00000001');
    });
    test('invoices come oldest first', () {
      final found = parseEInvoices(
        '$head'
        '20261005,CD00000002,甲店,開立,甲,20\n'
        '20261001,CD00000001,甲店,開立,乙,10\n',
      );
      expect(found.map((i) => i.number), ['CD00000001', 'CD00000002']);
    });
    test('a row that cannot be read stops the whole file, naming its line', () {
      expect(
        () => parseEInvoices(
          '$head'
          '20261003,CD00000001,甲店,開立,甲,10\n'
          '2026-10-03,CD00000002,甲店,開立,乙,20\n',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Line 3'),
          ),
        ),
      );
    });
    test('a missing amount column is an error', () {
      expect(
        () => parseEInvoices('發票日期,發票號碼\n20261003,CD00000001\n'),
        throwsFormatException,
      );
    });
  });

  group('the ministry CSV, imported as spending', () {
    test('one invoice becomes one expense with its note and merchant', () {
      final found = invoices(
        book(),
        '$head'
        '20261003,CD00000001,全聯福利中心,開立,鮮奶,199\n'
        '20261003,CD00000001,全聯福利中心,開立,吐司,69\n',
      );
      final e = found.entries.single;
      expect(e.type, EntryType.expense);
      expect(e.amount, 268);
      expect(e.merchant, '全聯福利中心');
      expect(e.date, day(2026, 10, 3));
      expect(e.account, 'bank');
      expect(e.note, '鮮奶 等 2 項 發票 CD00000001');
      expect(e.tags, contains('發票'));
    });
    test('a voided invoice is counted as left out', () {
      final found = invoices(
        book(),
        '$head'
        '20261003,CD00000001,甲店,開立,鮮奶,199\n'
        '20261004,CD00000002,乙店,作廢,飲料,50\n',
      );
      expect(found.entries.map((e) => e.amount), [199]);
    });
    test('an invoice already booked is not booked again', () {
      final ledger = book();
      const text = '${head}20261003,CD00000001,甲店,開立,鮮奶,199\n';
      final first = invoices(ledger, text);
      ledger.entryCommands.addAll(first.entries);
      final again = invoices(ledger, text);
      expect(again.entries, isEmpty);
      expect(again.skipped, 1);
    });
    test('the same invoice number twice in a file is booked once', () {
      final found = invoices(
        book(),
        '$head'
        '20261003,CD00000001,甲店,開立,鮮奶,199\n'
        '20261003,CD00000001,甲店,開立,鮮奶,199\n',
      );
      // Rows of one number are one invoice: 199 + 199 = 398 in one entry.
      expect(found.entries, hasLength(1));
      expect(found.entries.single.amount, 398);
    });
    test('a fuel merchant takes the transport category the book has', () {
      final found = invoices(
        book(),
        '${head}20261004,CD00000003,中油加油站,開立,95無鉛,900\n',
      );
      expect(found.entries.single.category, '交通通勤');
    });
    test('an unknown merchant takes 其他支出', () {
      final found = invoices(
        book(),
        '${head}20261004,CD00000004,某店,開立,東西,50\n',
      );
      expect(found.entries.single.category, '其他支出');
    });
    test('a foreign-currency account is refused, nothing is booked', () {
      final found = invoices(
        book(),
        '${head}20261003,CD00000001,甲店,開立,鮮奶,199\n',
        account: 'usd',
      );
      expect(found.entries, isEmpty);
      expect(found.problems, ['電子發票是新台幣，請選新台幣帳戶付款']);
    });
    test('a file with a bad row books nothing', () {
      final found = invoices(
        book(),
        '$head'
        '20261003,CD00000001,甲店,開立,甲,10\n'
        'bad,CD00000002,甲店,開立,乙,20\n',
      );
      expect(found.entries, isEmpty);
      expect(found.problems, ['檔案格式看不懂']);
    });
  });

  group('the M and D lines', () {
    const lines =
        'M|手機條碼|/ABC123|20261003|12345678|全聯福利中心|AB00000001|268|開立\n'
        'D|AB00000001|199|鮮奶\n'
        'D|AB00000001|69|吐司\n'
        'M|手機條碼|/ABC123|20261004|87654321|某店|AB00000003|50|作廢\n';
    test('the total comes from the M line, the note from the D lines', () {
      final found = invoices(book(), lines);
      expect(found.entries, hasLength(1));
      final e = found.entries.single;
      expect(e.amount, 268);
      expect(e.merchant, '全聯福利中心');
      expect(e.date, day(2026, 10, 3));
      expect(e.note, '鮮奶 等 2 項 發票 AB00000001');
    });
    test('a voided M line is skipped and says so', () {
      final found = invoices(book(), lines);
      expect(found.skipped, 1);
      expect(found.problems, ['AB00000003：已作廢']);
    });
    test('an M line with a zero total is skipped', () {
      final found = invoices(
        book(),
        'M|手機條碼|/ABC123|20261003|12345678|甲店|AB00000009|0|開立\n',
      );
      expect(found.entries, isEmpty);
      expect(found.problems, ['AB00000009：金額看不懂']);
    });
    test('an M line with an impossible date is skipped', () {
      final found = invoices(
        book(),
        'M|手機條碼|/ABC123|20261340|12345678|甲店|AB00000009|50|開立\n',
      );
      expect(found.entries, isEmpty);
      expect(found.problems, ['AB00000009：日期看不懂']);
    });
  });
}
