import 'dart:convert';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:domain/accounts.dart';
import 'package:domain/bookkeeping.dart';
import 'package:domain/budgets.dart';
import 'package:domain/categories.dart';
import 'package:domain/credit_cards.dart';
import 'package:domain/investments.dart';
import 'package:domain/ledger.dart';
import 'package:domain/merchants.dart';
import 'package:domain/recurring_transactions.dart';
import 'package:domain/reports.dart';
import 'package:domain/tags.dart';
import 'package:storage/storage_sqlcipher.dart';

part 'schema.dart';
part 'book_queries.dart';
part 'card_queries.dart';
part 'investment_queries.dart';
part 'report_queries.dart';
part 'sql_bookkeeping.dart';

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
