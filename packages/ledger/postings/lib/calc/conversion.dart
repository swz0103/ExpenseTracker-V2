import 'package:core/foundation_values.dart' show Currency, Money;
import 'package:kernel/kernel.dart';

import '../model/intents.dart';

/// A line that is not in the currency it must be in, and the one it
/// must be in: a money account's line in another currency than the
/// account's, or a category's line in another than the book's. A line
/// of nothing needs none: the journal drops it.
typedef Misplaced = ({int index, CurrencyCode target, bool money});

/// The lines of [lines] that need converting.
List<Misplaced> misplaced(
  List<Line> lines,
  AccountTree accounts,
  CurrencyCode home,
) => [
  for (final (i, line) in lines.indexed)
    if (line.amount != 0)
      if (accounts[line.account] case final account?)
        if (account.currency case final own? when own != line.currency)
          (index: i, target: own, money: true)
        else if (account.currency == null &&
            account.cls.isFlow &&
            line.currency != home)
          (index: i, target: home, money: false),
];

/// [lines] with those [misplaced] restated in their own currency by
/// [value], the far side of each currency on [trading]: so that each
/// currency still comes to zero by itself. A refusal names the slot
/// [slot], for a form to show under its field.
Posted restate(
  List<Line> lines, {
  required AccountTree accounts,
  required CurrencyCode home,
  required ForeignValue? value,
  required AccountId trading,
  required String slot,
}) {
  final todo = misplaced(lines, accounts, home);
  if (todo.isEmpty) {
    return value == null ? Lines(lines) : Refused('fx.unused', slot);
  }
  if (value == null) return Refused('fx.needed', slot);
  final out = [...lines];
  final extra = <Line>[];
  void convert(List<Misplaced> some, int worth) {
    final source = {for (final m in some) lines[m.index].currency};
    final target = {for (final m in some) m.target};
    final signs = {for (final m in some) lines[m.index].amount.sign};
    if (source.length != 1 || target.length != 1 || signs.length != 1) {
      throw const _Refusal('fx.ambiguous');
    }
    final sign = signs.single;
    final to = target.single;
    final shares = Money(Currency.of(to.value), BigInt.from(worth)).allocate([
      for (final m in some) BigInt.from(lines[m.index].amount.abs()),
    ]);
    var sent = 0;
    for (final (k, m) in some.indexed) {
      sent += lines[m.index].amount;
      out[m.index] = lines[m.index].restated(
        sign * shares[k].minorUnits.toInt(),
        to,
      );
    }
    extra
      ..add(Line(trading, sent, source.single))
      ..add(Line(trading, -sign * worth, to));
  }

  void sameNumber(Misplaced m) {
    final line = lines[m.index];
    out[m.index] = line.restated(line.amount, m.target);
    extra
      ..add(Line(trading, line.amount, line.currency))
      ..add(Line(trading, -line.amount, m.target));
  }

  try {
    switch (value) {
      case Worth(:final amount):
        if (amount <= 0) return Refused('fx.badAmount', slot);
        // One value cannot say both what a transfer received and what
        // its fee was worth.
        if ({for (final m in todo) m.money}.length != 1) {
          return Refused('fx.ambiguous', slot);
        }
        convert(todo, amount);
      case SameNumber():
        todo.forEach(sameNumber);
      case ReceivedFeeSameNumber(:final received):
        if (received <= 0) return Refused('fx.badAmount', slot);
        final money = [
          for (final m in todo)
            if (m.money) m,
        ];
        if (money.isEmpty) return Refused('fx.unused', slot);
        convert(money, received);
        todo.where((m) => !m.money).forEach(sameNumber);
    }
  } on _Refusal catch (refusal) {
    return Refused(refusal.code, slot);
  }
  return Lines([...out, ...extra]);
}

/// Leaves [restate] for a refusal found inside it.
final class _Refusal implements Exception {
  const _Refusal(this.code);
  final String code;
}
