import 'package:domain/data_exchange.dart';
import 'package:test/test.dart';

void main() {
  test('the NT\$ worth column keeps the name files were written with', () {
    expect(homeAmountColumn, '台幣金額');
  });
}
