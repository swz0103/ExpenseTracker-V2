import 'package:market_data/market_data.dart';

final class InvestmentMarketServices {
  const InvestmentMarketServices({required this.gateway, required this.router});

  final MarketDataGateway gateway;
  final MarketDataRouter router;
}

InvestmentMarketServices createInvestmentMarketServices() {
  final gateway = MarketDataGateway();
  final registry = MarketProviderRegistry([
    TwseStockCloseProvider(gateway),
    TpexStockCloseProvider(gateway),
    EcbReferenceFxProvider(gateway),
    CbcUsdTwdReferenceFxProvider(gateway),
  ]);
  return InvestmentMarketServices(
    gateway: gateway,
    router: MarketDataRouter(registry),
  );
}
