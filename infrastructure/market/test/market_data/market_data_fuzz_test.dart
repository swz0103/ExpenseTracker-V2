import 'dart:io';
import 'dart:math';

import 'package:core/foundation_values.dart';
import 'package:market/market_data.dart';
import 'package:test/test.dart';

final class _Body implements MarketTransport {
  _Body(this.body);

  final String body;

  @override
  Future<MarketResponse> get(Uri uri) async => MarketResponse(200, body);
}

/// R12 F7 (D95): the exchanges' and the bank's pages mutated at random
/// (seeded). Reading them never throws, and nothing read is dated after
/// today. A few hundred cases here; `FUZZ_CASES=30000` for a nightly run.
void main() {
  final cases = int.tryParse(Platform.environment['FUZZ_CASES'] ?? '') ?? 300;
  final today = BusinessDate(2026, 10, 4);
  const daily =
      '[{"Date":"1151002","Code":"2330","Name":"台積電",'
      '"ClosingPrice":"1,234.50","Change":"-5.5000"}]';
  const month =
      '{"stat":"OK","fields":["日期","成交股數","收盤價","漲跌價差"],'
      '"data":[["115/09/30","1","100.5","+1.0"],["115/10/01","1","101.0","+0.5"]]}';
  const fragments = [
    '[', ']', '{', '}', '"', ',', ':', 'null', '1e999', '-1', '0', '1,234', //
    '--', 'NaN', '99999999999999999999', '0.000000000001', '1151099',
    '9991231', '1161231', '116/01/01', '115/13/40', 'Date', 'ClosingPrice',
    '2330', '日期', '收盤價', 'OK', '\u0000', '😀', ' ',
  ];

  String mutate(Random r, String text) {
    var t = text;
    for (var k = 1 + r.nextInt(4); k > 0; k--) {
      final at = t.isEmpty ? 0 : r.nextInt(t.length);
      final piece = fragments[r.nextInt(fragments.length)];
      t = switch (r.nextInt(3)) {
        0 => t.substring(0, at) + piece + t.substring(at),
        1 => t.substring(0, at),
        _ =>
          t.substring(0, at) +
              piece +
              t.substring(min(t.length, at + 1 + r.nextInt(8))),
      };
    }
    return t;
  }

  test('$cases pages: read, or refused; never dated after today', () async {
    final r = Random(99);
    for (var i = 0; i < cases; i++) {
      final daySource = mutate(r, daily);
      final monthSource = mutate(r, month);
      MarketDataGateway on(String body) => MarketDataGateway(
        transport: _Body(body),
        clock: () => DateTime.utc(2026, 10, 4, 4),
      );
      final close = await on(daySource).stockClose(const Listing('2330'));
      if (close.value case final value?) {
        expect(value.asOf.compareTo(today), lessThanOrEqualTo(0));
      }
      final last = await on(monthSource).listedHistoryClose('2330');
      if (last.value case final value?) {
        expect(value.asOf.compareTo(today), lessThanOrEqualTo(0));
      }
      final days = await on(monthSource).monthCloses('2330', 2026, 10);
      for (final day in days.value ?? const <DayClose>[]) {
        expect(day.date.compareTo(today), lessThanOrEqualTo(0));
      }
    }
  });
}
