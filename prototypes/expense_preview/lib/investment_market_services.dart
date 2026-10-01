import 'package:market_data/market_data.dart';

final class InvestmentMarketServices {
  const InvestmentMarketServices({required this.gateway, required this.router});

  final MarketDataGateway gateway;
  final MarketDataRouter router;
}

InvestmentMarketServices createInvestmentMarketServices() {
  final gateway = MarketDataGateway();
  final frankfurter = FrankfurterReferenceFxGateway();
  final registry = MarketProviderRegistry([
    TwseStockCloseProvider(gateway),
    TpexStockCloseProvider(gateway),
    EcbReferenceFxProvider(gateway),
    CbcUsdTwdReferenceFxProvider(gateway),
    FrankfurterReferenceFxProvider(frankfurter),
  ]);
  return InvestmentMarketServices(
    gateway: gateway,
    router: MarketDataRouter(registry),
  );
}
