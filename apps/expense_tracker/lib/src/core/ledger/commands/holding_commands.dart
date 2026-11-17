import '../cache/topic.dart';
import '../models/models.dart';
import '../repositories/entry_repository.dart';
import '../repositories/holding_repository.dart';
import '../repositories/market_data_repository.dart';
import 'command_context.dart';

/// Writes the market data and the holdings resting on it.
final class HoldingCommands {
  HoldingCommands({
    required this._context,
    required MarketDataRepository marketRepository,
    required HoldingRepository holdingRepository,
    required EntryRepository entryRepository,
  }) : _market = marketRepository,
       _holdings = holdingRepository,
       _entries = entryRepository;

  final CommandContext _context;
  final MarketDataRepository _market;
  final HoldingRepository _holdings;
  final EntryRepository _entries;

  /// Takes new closing prices and rates: the stocks' reference prices and
  /// names in [holdings], each day's change in [moves].
  void setMarket({
    required List<Holding> holdings,
    required Map<String, double> moves,
    required Map<String, double> rates,
    DateTime? quotedOn,
    Map<String, DateTime> quoteDays = const {},
  }) {
    _market.replace(
      rates: rates,
      moves: moves,
      quotedOn: quotedOn,
      quoteDays: quoteDays,
    );
    _holdings
      ..replaceStart(holdings)
      ..replay(_entries, lenient: true);
    _context.changed(const {Topic.market});
  }
}
