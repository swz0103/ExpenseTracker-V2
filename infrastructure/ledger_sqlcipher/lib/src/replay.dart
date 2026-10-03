import 'dart:convert';

import 'package:bookkeeping/bookkeeping.dart';
import 'package:budgets/budgets.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:recurring_transactions/recurring_transactions.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';

import 'ledger_store.dart';

/// An event the replayer does not understand. Replay stops instead of
/// skipping it, because a skipped event would silently change balances.
final class ReplayException implements Exception {
  const ReplayException(this.seq, this.kind, this.reason);

  final int seq;
  final String kind;
  final String reason;

  @override
  String toString() => 'ReplayException(#$seq $kind: $reason)';
}

/// Rebuilds a ledger from its event journal.
///
/// Every event already carries the full new state of what it changed, so
/// replaying the journal in order into an empty store reproduces every
/// projection table. Each payload is decoded through the domain codecs on
/// the way in, so a corrupt or rule-breaking event is caught here.
abstract final class LedgerReplay {
  /// Copies [from]'s journal and operation records into the empty store
  /// [to], rebuilding its projections. Returns the number of events copied.
  static Future<int> copy({
    required SqlCipherStore from,
    required LedgerStore to,
    int batch = 500,
  }) async {
    var copied = 0;
    var after = 0;
    while (true) {
      final page = from.journal(afterSeq: after, limit: batch);
      if (page.isEmpty) break;
      await to.write((transaction) async {
        for (final event in page) {
          await apply(transaction, event);
        }
      });
      copied += page.length;
      after = page.last.seq;
    }
    for (var offset = 0; ; offset += batch) {
      final operations = from.operations(offset: offset, limit: batch);
      if (operations.isEmpty) break;
      await to.write((transaction) async {
        for (final operation in operations) {
          await transaction.recordOperation(operation);
        }
      });
    }
    return copied;
  }

  /// Appends [event] to the transaction's journal and applies its effect to
  /// the projections.
  static Future<void> apply(SqlBookkeeping t, StoredEvent event) async {
    final Map<String, Object?> payload;
    try {
      payload = jsonDecode(event.payload) as Map<String, Object?>;
    } on Object {
      throw ReplayException(event.seq, event.kind, 'payload is not JSON');
    }
    await t.appendEvent(
      id: event.id,
      workspace: event.workspace,
      kind: event.kind,
      payload: event.payload,
    );
    try {
      await _project(t, event.kind, payload);
    } on ReplayException catch (error) {
      throw ReplayException(event.seq, error.kind, error.reason);
    } on Object catch (error) {
      throw ReplayException(event.seq, event.kind, '${error.runtimeType}');
    }
  }

  static Future<void> _project(
    SqlBookkeeping t,
    String kind,
    Map<String, Object?> p,
  ) async {
    Map<String, Object?> part(String key) => p[key]! as Map<String, Object?>;
    switch (kind) {
      case 'account.opened' ||
          'account.renamed' ||
          'account.archived' ||
          'account.reactivated' ||
          'account.closed':
        await t.saveAccount(AccountCodec.decode(p));
      case 'posting.recorded':
        await t.savePosting(
          PostingCodec.decode(part('posting')),
          PostingMetadata.fromJson(part('metadata')),
        );
      case 'posting.noted':
        await t.saveNote(
          PublicId.parse(p['postingId']! as String),
          EntryNote(p['revision']! as int, p['text']! as String),
        );
      case 'category.changed':
        await t.saveCategory(CatalogCodec.readCategory(p));
      case 'tag.changed':
        await t.saveTag(CatalogCodec.readTag(p));
      case 'merchant.changed':
        await t.saveMerchant(CatalogCodec.readMerchant(p));
      case 'card.terms-set':
        await t.saveCardTerms(
          const CreditCardTermsCodec().decode(p['terms']! as String),
        );
      case 'card.authorized' || 'card.posted':
        await t.saveCardCharge(CardRecords.readCharge(p));
      case 'card.paid':
        await t.saveCardPayment(CardRecords.readPayment(p));
      case 'card.installments-planned':
        await t.saveInstallmentPlan(
          const CardInstallmentScheduleCodec().decode(p['plan']! as String),
        );
      case 'investment.broker-registered':
        await t.saveBroker(InvestmentRecords.readBroker(part('broker')));
      case 'investment.account-opened':
        await t.saveInvestmentAccount(
          InvestmentRecords.readAccount(part('account')),
        );
      case 'investment.listed':
        await t.saveInstrument(
          InvestmentRecords.readInstrument(part('instrument')),
        );
      case 'investment.traded':
        await t.saveTrade(p);
      case 'budget.set':
        await t.saveBudget(BudgetPlanCodec().decode(p['plan']! as String));
      case 'recurring.saved':
        await t.saveRecurring(
          RecurringTemplateCodec().decode(p['template']! as String),
          active: p['active']! as bool,
        );
      case 'recurring.confirmed':
        await t.saveConfirmation(
          PublicId.parse(p['templateId']! as String),
          BusinessDate.parse(p['dueDate']! as String),
          PublicId.parse(p['postingId']! as String),
        );
      default:
        throw ReplayException(0, kind, 'unknown event kind');
    }
  }
}

/// Every projection table, for comparing two stores row by row.
const ledgerTables = {
  'ledger_accounts': 'id',
  'ledger_postings': 'id',
  'ledger_legs': 'posting_id, leg',
  'ledger_balances': 'account_id',
  'ledger_monthly': 'workspace, month, currency, scale',
  'ledger_category_monthly': 'workspace, month, category_id, currency, scale',
  'ledger_posting_tags': 'posting_id, tag_id',
  'ledger_posting_merchants': 'posting_id',
  'ledger_notes': 'posting_id',
  'catalog_entries': 'type, id',
  'card_terms': 'card_id',
  'card_charges': 'id',
  'card_payments': 'id',
  'card_installment_plans': 'purchase_posting_id',
  'invest_registry': 'type, id',
  'invest_listings': 'market, symbol',
  'invest_trades': 'seq',
  'plan_budgets': 'id',
  'plan_recurring': 'id',
  'plan_recurring_confirmed': 'template_id, due_date',
};

/// The rows of every projection table in key order, as plain values.
Map<String, List<Map<String, Object?>>> projectionRows(SqlCipherStore store) =>
    {
      for (final MapEntry(key: table, value: order) in ledgerTables.entries)
        table: store.select('SELECT * FROM $table ORDER BY $order'),
    };
