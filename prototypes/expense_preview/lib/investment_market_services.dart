import 'package:market_data/market_data.dart';

import 'market_credentials.dart';
import 'price_alert_service.dart';

final class InvestmentMarketServices {
  const InvestmentMarketServices({
    required this.gateway,
    required this.router,
    this.fugleCredentials,
    this.priceAlerts,
    this.priceAlertNotifications,
  });

  final MarketDataGateway gateway;
  final MarketDataRouter router;
  final FugleCredentialManager? fugleCredentials;
  final PriceAlertService? priceAlerts;
  final PriceAlertNotificationPresenter? priceAlertNotifications;
}

InvestmentMarketServices createInvestmentMarketServices({
  FugleCredentialManager? fugleCredentials,
  PriceAlertService? priceAlerts,
  PriceAlertNotificationPresenter? priceAlertNotifications,
}) {
  final gateway = MarketDataGateway();
  final frankfurter = FrankfurterReferenceFxGateway();
  final registry = MarketProviderRegistry([
    if (fugleCredentials != null)
      FugleIntradayStockProvider(
        FugleIntradayGateway(apiKeySource: fugleCredentials.requireApiKey),
      ),
    TwseStockCloseProvider(gateway),
    TpexStockCloseProvider(gateway),
    EcbReferenceFxProvider(gateway),
    CbcUsdTwdReferenceFxProvider(gateway),
    FrankfurterReferenceFxProvider(frankfurter),
  ]);
  return InvestmentMarketServices(
    gateway: gateway,
    router: MarketDataRouter(registry),
    fugleCredentials: fugleCredentials,
    priceAlerts: priceAlerts,
    priceAlertNotifications: priceAlertNotifications,
  );
}
