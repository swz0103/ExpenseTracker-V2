/// Review 22 finding 3: the chart's months of closes are kept sealed with
/// the ledger's key, in one file that names no stock; a file another key
/// sealed (after a restore or a reset) or the plain folder of an older
/// version is taken away as the ledger opens.
library;

import 'dart:convert';
import 'dart:io';

import 'package:expense_tracker/src/features/investments/model/price_months.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/backup_security.dart';

void main() {
  late Directory directory;
  late FileBox box;
  late FileBox otherBox;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('price-months-');
    final codec = KeyringCodec(kdf: PasswordKdf.insecureForTests);
    box = await FileBox.derive(
      (await codec.create('first ledger')).unlocked,
      FileBox.prices,
    );
    otherBox = await FileBox.derive(
      (await codec.create('other ledger')).unlocked,
      FileBox.prices,
    );
  });
  tearDown(() => directory.deleteSync(recursive: true));

  File sealed() => File('${directory.path}/${PriceMonths.name}');

  final august = <String, CodeMonths>{
    '2330': (
      otc: false,
      months: {
        '2026-08': [(DateTime.utc(2026, 8, 28), 1100.0)],
      },
    ),
    '6488': (otc: true, months: {'2026-08': <(DateTime, double)>[]}),
  };

  test('written sealed, read back as written', () async {
    await PriceMonths(directory, box).write(august);
    expect(latin1.decode(sealed().readAsBytesSync()), isNot(contains('2330')));
    final read = await PriceMonths(directory, box).read();
    expect(read.keys, ['2330', '6488']);
    expect(read['2330']!.otc, isFalse);
    expect(read['2330']!.months, {
      '2026-08': [(DateTime.utc(2026, 8, 28), 1100.0)],
    });
    expect(read['6488']!.otc, isTrue);
    // Nothing left beside it.
    expect(directory.listSync(), hasLength(1));
  });

  test('a file another key sealed goes as the ledger opens', () async {
    await PriceMonths(directory, otherBox).write(august);
    expect(sealed().existsSync(), isTrue);
    final months = PriceMonths(directory, box);
    await months.settle();
    expect(sealed().existsSync(), isFalse);
    expect(await months.read(), isEmpty);
  });

  test('the plain files of an older version go as the ledger opens, and a '
      'file this key sealed stays', () async {
    final plain = Directory('${directory.path}/prices')..createSync();
    File('${plain.path}/2330.json').writeAsStringSync('{"months":{}}');
    await PriceMonths(directory, box).write(august);
    await PriceMonths(directory, box).settle();
    expect(plain.existsSync(), isFalse);
    expect(sealed().existsSync(), isTrue);
  });

  test('writes go one after another, the last kept', () async {
    final months = PriceMonths(directory, box);
    final only2330 = {'2330': august['2330']!};
    await Future.wait([months.write(only2330), months.write(august)]);
    expect((await PriceMonths(directory, box).read()).keys, ['2330', '6488']);
  });

  test('a close that is not a day and a price makes the file unreadable, '
      'and it goes', () async {
    sealed().writeAsBytesSync(
      await box.seal(
        PriceMonths.name,
        utf8.encode(
          jsonEncode({
            'codes': {
              '2330': {
                'otc': false,
                'months': {
                  '2026-08': [
                    ['2026-08-28'],
                  ],
                },
              },
            },
          }),
        ),
      ),
    );
    expect(await PriceMonths(directory, box).read(), isEmpty);
    expect(sealed().existsSync(), isFalse);
  });

  test('with nothing kept there is nothing to read', () async {
    final months = PriceMonths(directory, box);
    await months.settle();
    expect(await months.read(), isEmpty);
  });
}
