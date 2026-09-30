import 'package:market_data/market_data.dart';

import 'market_credentials.dart';
import 'twelve_data_credentials.dart';

final class InvestmentMarketServices {
  const InvestmentMarketServices({
    required this.gateway,
    required this.router,
    required this.fugleCredentials,
    required this.twelveDataCredentials,
  });

  final MarketDataGateway gateway;
  final MarketDataRouter router;
  final FugleCredentialManager fugleCredentials;
  final TwelveDataCredentialManager twelveDataCredentials;
}

InvestmentMarketServices createInvestmentMarketServices() {
  final gateway = MarketDataGateway();
  final fugleCredentials = FugleCredentialManager(
    AndroidFugleCredentialVault(),
  );
  final twelveDataCredentials = TwelveDataCredentialManager(
    AndroidTwelveDataCredentialVault(),
  );
  final registry = MarketProviderRegistry([
    TwseStockCloseProvider(gateway),
    TpexStockCloseProvider(gateway),
    EcbReferenceFxProvider(gateway),
    CbcUsdTwdReferenceFxProvider(gateway),
    FugleIntradayStockProvider(
      FugleIntradayGateway(apiKeySource: fugleCredentials.requireApiKey),
    ),
    TwelveDataIntradayStockProvider(
      TwelveDataIntradayGateway(
        apiKeySource: twelveDataCredentials.requireApiKey,
      ),
    ),
  ]);
  return InvestmentMarketServices(
    gateway: gateway,
    router: MarketDataRouter(registry),
    fugleCredentials: fugleCredentials,
    twelveDataCredentials: twelveDataCredentials,
  );
}
