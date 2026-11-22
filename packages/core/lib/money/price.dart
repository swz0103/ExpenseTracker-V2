/// Amounts worked out from a price, exactly. A close comes as a decimal
/// (662.05) that a double holds only nearly: 2,730 shares at 662.05 is
/// 1,807,396.5, which as doubles is 1,807,396.4999... and would round
/// the wrong way. The price is taken to 1/10,000, which every published
/// close has room for, and the product is then whole numbers only.
library;

import '../percent/percent.dart' show divideRounded;

/// Steps of a price: 1/10,000 of the currency's unit.
const priceScale = 10000;

/// [price] in steps of [priceScale]: 662.05 → 6,620,500.
int scaledPrice(double price) => (price * priceScale).round();

/// [count] of something at [price] each, in whole units, rounded half
/// away from zero: 2,730 at 662.05 → 1,807,397.
int timesPrice(int count, double price) =>
    divideRounded(count * scaledPrice(price), priceScale);
