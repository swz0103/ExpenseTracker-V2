import 'dart:convert';

import 'package:accounts/accounts.dart';
import 'package:app_core/app_core.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:budgets/budgets.dart';
import 'package:categories/categories.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:ledger/ledger.dart';
import 'package:merchants/merchants.dart';
import 'package:recurring_transactions/recurring_transactions.dart';
import 'package:reports/reports.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';
import 'package:tags/tags.dart';

part 'schema.dart';
part 'card_queries.dart';
part 'investment_queries.dart';
part 'report_queries.dart';
part 'sql_bookkeeping.dart';

/// Income and expense for one month in one currency, as reported totals.
final class MonthlyTotal {
  const MonthlyTotal(this.income, this.expense);

  final Money income;
  final Money expense;
}

/// Realized results and net dividends over a period, in one currency.
final class InvestmentIncome {
  const InvestmentIncome({required this.realized, required this.dividends});

  final Money realized;
  final Money dividends;
}

Money _zero(Money like) => Money(like.currency, BigInt.zero);

/// Dividends of one holding over a year, in its currency.
final class DividendTotal {
  const DividendTotal({
    required this.accountId,
    required this.instrumentId,
    required this.gross,
    required this.withholdingTax,
    required this.fee,
    required this.healthPremium,
    required this.net,
    required this.payments,
  });

  final PublicId accountId;
  final PublicId instrumentId;
  final Money gross;
  final Money withholdingTax;
  final Money fee;
  final Money healthPremium;
  final Money net;
  final int payments;

  DividendTotal plus(DividendTotal other) => DividendTotal(
    accountId: accountId,
    instrumentId: instrumentId,
    gross: gross + other.gross,
    withholdingTax: withholdingTax + other.withholdingTax,
    fee: fee + other.fee,
    healthPremium: healthPremium + other.healthPremium,
    net: net + other.net,
    payments: payments + other.payments,
  );
}

/// Bookkeeping on one SQLCipher store. Open the store with [ledgerSchema].
final class LedgerStore implements UnitOfWork<SqlBookkeeping> {
  LedgerStore(this._store) {
    if (_store.moduleVersion(ledgerSchema.name) !=
        ledgerSchema.migrations.length) {
      throw StateError('Open the store with ledgerSchema.');
    }
  }

  final SqlCipherStore _store;

  /// The underlying store, for journal-level work such as backups.
  SqlCipherStore get store => _store;

  @override
  Future<R> write<R>(Future<R> Function(SqlBookkeeping transaction) body) =>
      _store.write((transaction) => body(SqlBookkeeping._(transaction)));

  List<Account> accounts(WorkspaceId workspace) {
    final rows = _store.select(
      'SELECT payload FROM ledger_accounts WHERE workspace = ? ORDER BY id',
      [workspace.toString()],
    );
    return [for (final row in rows) _decodeAccount(row['payload'])];
  }

  Money balance(Account account) {
    final rows = _store.select(
      'SELECT minor_units FROM ledger_balances WHERE account_id = ?',
      [account.id.value],
    );
    return _balance(account.currency, rows);
  }

  /// Every posting that touches [accountId], oldest first.
  List<Posting> postings(PublicId accountId) {
    final rows = _store.select(
      'SELECT p.payload FROM ledger_postings p '
      'WHERE p.id IN (SELECT posting_id FROM ledger_legs WHERE account_id = ?) '
      'ORDER BY p.date, p.id',
      [accountId.value],
    );
    return [for (final row in rows) _decodePosting(row['payload'])];
  }

  /// The newest postings in [workspace], newest first.
  List<Posting> recentPostings(WorkspaceId workspace, {int limit = 30}) {
    final rows = _store.select(
      'SELECT payload FROM ledger_postings WHERE workspace = ? '
      'ORDER BY date DESC, id DESC LIMIT ?',
      [workspace.toString(), limit],
    );
    return [for (final row in rows) _decodePosting(row['payload'])];
  }

  List<Category> categories(WorkspaceId workspace) => [
    for (final json in _catalog('category', workspace))
      CatalogCodec.readCategory(json),
  ];

  List<Tag> tags(WorkspaceId workspace) => [
    for (final json in _catalog('tag', workspace)) CatalogCodec.readTag(json),
  ];

  List<Merchant> merchants(WorkspaceId workspace) => [
    for (final json in _catalog('merchant', workspace))
      CatalogCodec.readMerchant(json),
  ];

  EntryNote note(PublicId postingId) => _readNote(_store.select, postingId);

  /// Whether [postingId] has been reversed, and by which posting.
  PublicId? reversedBy(PublicId postingId) {
    final rows = _store.select(
      'SELECT id FROM ledger_postings WHERE reversal_of = ?',
      [postingId.value],
    );
    return rows.isEmpty ? null : PublicId.parse(rows.single['id']! as String);
  }

  /// Every posting that touches [account], oldest first, with the
  /// account's balance after it.
  List<(Posting, Money)> runningBalance(Account account) {
    final rows = _store.select(
      'SELECT p.payload, group_concat(l.minor_units) AS legs '
      'FROM ledger_postings p JOIN ledger_legs l ON l.posting_id = p.id '
      'WHERE l.account_id = ? GROUP BY p.id ORDER BY p.date, p.id',
      [account.id.value],
    );
    var balance = BigInt.zero;
    final lines = <(Posting, Money)>[];
    for (final row in rows) {
      for (final leg in (row['legs']! as String).split(',')) {
        balance += BigInt.parse(leg);
      }
      final after = Money(account.currency, balance);
      lines.add((_decodePosting(row['payload']), after));
    }
    return lines;
  }

  PostingMetadata metadata(PublicId postingId) =>
      _readMetadata(_store.select, postingId);

  List<Map<String, Object?>> _catalog(String type, WorkspaceId workspace) {
    final rows = _store.select(
      'SELECT payload FROM catalog_entries WHERE type = ? AND workspace = ?',
      [type, workspace.toString()],
    );
    return [for (final row in rows) _json(row['payload'])];
  }
}
