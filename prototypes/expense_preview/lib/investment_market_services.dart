import 'package:market_data/market_data.dart';

import 'price_alert_service.dart';

final class InvestmentMarketServices {
  const InvestmentMarketServices({
    required this.gateway,
    required this.router,
    this.priceAlerts,
  });

  final MarketDataGateway gateway;
  final MarketDataRouter router;
  final PriceAlertService? priceAlerts;
}

InvestmentMarketServices createInvestmentMarketServices({
  PriceAlertService? priceAlerts,
}) {
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
    priceAlerts: priceAlerts,
  );
}
