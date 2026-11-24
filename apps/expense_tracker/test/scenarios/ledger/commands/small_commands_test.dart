import 'package:expense_tracker/src/core/ledger/cache/topic.dart';
import 'package:expense_tracker/src/core/ledger/commands/attachment_commands.dart';
import 'package:expense_tracker/src/core/ledger/commands/budget_commands.dart';
import 'package:expense_tracker/src/core/ledger/commands/holding_commands.dart';
import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:expense_tracker/src/core/ledger/persistence/write_batch.dart';
import 'package:expense_tracker/src/core/ledger/repositories/budget_repository.dart';
import 'package:expense_tracker/src/core/ledger/repositories/draft_repository.dart';
import 'package:expense_tracker/src/core/ledger/repositories/entry_repository.dart';
import 'package:expense_tracker/src/core/ledger/repositories/holding_repository.dart';
import 'package:expense_tracker/src/core/ledger/repositories/market_data_repository.dart';
import 'package:expense_tracker/src/core/ledger/repositories/receipt_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/book.dart';
import '../../../support/recording_context.dart';

void main() {
  group('BudgetCommands', () {
    test('a budget set is kept from this month, then keeps its start', () {
      final context = RecordingContext(day);
      final budgets = BudgetRepository();
      final commands = BudgetCommands(
        context: context,
        budgetRepository: budgets,
      );
      commands.setBudget('飲食', 3000);
      expect(budgets.forCategory('飲食').since, DateTime.utc(2026, 10));
      context.today = DateTime.utc(2026, 12, 2);
      commands.setBudget('飲食', 4000, carry: true);
      final kept = budgets.forCategory('飲食');
      expect(
        (kept.limit, kept.carry, kept.since),
        (4000, true, DateTime.utc(2026, 10)),
      );
      expect(context.changes, [
        {Topic.budgets},
        {Topic.budgets},
      ]);
      expect(context.batches.last.budgets.single.limit, 4000);
    });

    test('a budget removed is dropped by what it covers', () {
      final context = RecordingContext(day);
      final budgets = BudgetRepository([Budget('#家用', 100)]);
      BudgetCommands(
        context: context,
        budgetRepository: budgets,
      ).removeBudget('#家用');
      expect(budgets.all, isEmpty);
      expect(context.batches.single.dropped, [(Collection.budget, '#家用')]);
    });
  });

  group('AttachmentCommands', () {
    AttachmentCommands make(RecordingContext context) => AttachmentCommands(
      context: context,
      receiptRepository: ReceiptRepository({'e1': 'a.jpg'}),
      draftRepository: DraftRepository({'expense': '{"receipt":"d.jpg"}'}),
    );

    test('the photos to keep include those chosen on forms put aside', () {
      expect(make(RecordingContext(day)).receiptFiles, {'a.jpg', 'd.jpg'});
    });

    test('a photo set is kept and shown; the same again is nothing', () {
      final context = RecordingContext(day);
      final commands = make(context);
      commands.setReceipt('e1', 'b.jpg');
      commands.setReceipt('e1', 'b.jpg');
      expect(context.signals, 1);
      expect(context.batches.single.receipts, {'e1': 'b.jpg'});
    });

    test('a form put aside is kept but no sum changes', () {
      final context = RecordingContext(day);
      make(context).setDraft('income', '{}');
      expect(context.changes, isEmpty);
      expect(context.signals, 0);
      expect(context.batches.single.onlyDrafts, isTrue);
    });
  });

  group('HoldingCommands', () {
    test('new market data replays the holdings and tells of it', () {
      final context = RecordingContext(day);
      final market = MarketDataRepository();
      final entries = EntryRepository([
        Entry(
          id: 'b',
          date: day,
          type: EntryType.buy,
          amount: 900,
          account: 'bank',
          holding: '2330',
          shares: 10,
        ),
      ]);
      final holdings = HoldingRepository(const [], moveOf: market.moveOf)
        ..replay(entries.all, today: day);
      HoldingCommands(
        context: context,
        marketRepository: market,
        holdingRepository: holdings,
        entryRepository: entries,
      ).setMarket(
        holdings: const [
          Holding('2330', '台積電', shares: 0, price: 100, cost: 0, change: 0),
        ],
        moves: {'2330': 2},
        rates: {'USD': 32},
        quotedOn: day,
      );
      expect(holdings.byCode('2330')?.change, 20);
      expect(holdings.hasQuote('2330'), isTrue);
      expect(market.rateOf('USD'), 32);
      expect(context.changes, [
        {Topic.market},
      ]);
      expect(context.batches, isEmpty);
    });
  });
}
