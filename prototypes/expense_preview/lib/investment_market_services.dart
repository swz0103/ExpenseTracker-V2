import 'package:market_adapters/market_adapters.dart';
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
    this.priceAlertBackground,
  });

  final MarketDataGateway gateway;
  final MarketDataRouter router;
  final FugleCredentialManager? fugleCredentials;
  final PriceAlertService? priceAlerts;
  final PriceAlertNotificationPresenter? priceAlertNotifications;
  final PriceAlertBackgroundScheduler? priceAlertBackground;
}

InvestmentMarketServices createInvestmentMarketServices({
  FugleCredentialManager? fugleCredentials,
  PriceAlertService? priceAlerts,
  PriceAlertNotificationPresenter? priceAlertNotifications,
  PriceAlertBackgroundScheduler? priceAlertBackground,
}) {
  final gateway = MarketDataGateway(transport: const IoMarketTransport());
  final frankfurter = FrankfurterReferenceFxGateway(
    transport: const IoMarketTransport(),
  );
  final registry = MarketProviderRegistry([
    YahooChartIntradayStockProvider(
      YahooChartIntradayGateway(transport: const IoYahooChartTransport()),
    ),
    if (fugleCredentials != null)
      FugleIntradayStockProvider(
        FugleIntradayGateway(
          apiKeySource: fugleCredentials.requireApiKey,
          transport: const IoFugleMarketTransport(),
        ),
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
    priceAlertBackground: priceAlertBackground,
  );
}
