import 'package:kernel/kernel.dart';

import '../model/intents.dart';
import '../model/vocabulary.dart';
import 'amenders.dart';
import 'money_rules.dart';
import 'trade_rules.dart';

/// Every kind of today's records and the two amenders, as the journal
/// posts them. [scheduleOf] gives each money account's billing days, for
/// instalments.
IntentRegistry todaysIntents({required ScheduleOf scheduleOf}) =>
    IntentRegistry()
      ..register<OpeningBalance>(
        const IntentSpec(
          type: OpeningBalance.kind,
          owner: Owners.accounts,
          rule: OpeningBalanceRule(),
        ),
      )
      ..register<Spending>(
        IntentSpec(
          type: Spending.kind,
          owner: Owners.entries,
          rule: const SpendingRule(),
          amendable: true,
          touches: (i) => [i.account],
        ),
      )
      ..register<Earning>(
        IntentSpec(
          type: Earning.kind,
          owner: Owners.entries,
          rule: const EarningRule(),
          amendable: true,
          touches: (i) => [i.account],
        ),
      )
      ..register<Transfer>(
        IntentSpec(
          type: Transfer.kind,
          owner: Owners.entries,
          rule: const TransferRule(),
          amendable: true,
          touches: (i) => [i.from, i.to],
        ),
      )
      ..register<OpeningPosition>(
        const IntentSpec(
          type: OpeningPosition.kind,
          owner: Owners.investments,
          rule: OpeningPositionRule(),
        ),
      )
      // Trades are amendable only so that an old book's trade paid from
      // a foreign account reads as today (a foreign value of SameNumber).
      ..register<Buy>(
        const IntentSpec(
          type: Buy.kind,
          owner: Owners.investments,
          rule: BuyRule(),
          amendable: true,
        ),
      )
      ..register<Sell>(
        const IntentSpec(
          type: Sell.kind,
          owner: Owners.investments,
          rule: SellRule(),
          amendable: true,
        ),
      )
      ..register<Dividend>(
        const IntentSpec(
          type: Dividend.kind,
          owner: Owners.investments,
          rule: DividendRule(),
          amendable: true,
        ),
      )
      ..register<OutOfHoldings>(
        const IntentSpec(
          type: OutOfHoldings.kind,
          owner: Owners.legacy,
          rule: OutOfHoldingsRule(),
          amendable: true,
        ),
      )
      ..amend(instalmentsAmender(scheduleOf))
      ..amend(fxAmender);
