import 'package:expense_preview/investment_market_services.dart';
import 'package:expense_preview/market_credentials.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:market_data/market_data.dart';
import 'package:flutter_test/flutter_test.dart';

final class _MemoryFugleVault implements FugleCredentialVault {
  String? value;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String apiKey) async => value = apiKey;
}

void main() {
  test(
    'production market services prefer no-key intraday and retain Fugle',
    () {
      final credentials = FugleCredentialManager(_MemoryFugleVault());
      final services = createInvestmentMarketServices(
        fugleCredentials: credentials,
      );
      final instrument = InvestmentInstrument(
        id: PublicId.generate(),
        kind: InstrumentKind.stock,
        marketCode: 'TWSE',
        symbol: '2330',
        name: '台積電',
        tradingCurrency: Currency('TWD', 2),
      );

      expect(services.fugleCredentials, same(credentials));
      final intraday = services.router.registry
          .intradayStockProviders(instrument, IntradayInterval.oneMinute)
          .map((provider) => provider.descriptor.id)
          .toList();
      expect(intraday.first, YahooChartIntradayStockProvider.providerId);
      expect(intraday, contains(FugleIntradayStockProvider.providerId));
      expect(
        services.router.registry
            .stockCloseProviders(instrument)
            .map((provider) => provider.descriptor.id),
        contains(StockClose.provider),
      );
    },
  );
}
