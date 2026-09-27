import 'dart:convert';

import 'package:accounts/accounts.dart';
import 'package:drift/drift.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'database.dart';

final class AccountsAdapter {
  AccountsAdapter(this.db);
  final ProbeDatabase db;
  Future<void> insert(Account account) =>
      db.customStatement('INSERT INTO accounts VALUES (?,?,?)', [
        account.workspace.toString(),
        account.id.value,
        jsonEncode(accountJson(account)),
      ]);
  Future<Account> read(WorkspaceId workspace, PublicId id) async {
    final rows = await db
        .customSelect(
          'SELECT payload FROM accounts WHERE workspace = ? AND id = ?',
          variables: [
            Variable.withString(workspace.toString()),
            Variable.withString(id.value),
          ],
        )
        .get();
    if (rows.isEmpty) throw const AccountException(AccountError.unavailable);
    final json =
        jsonDecode(rows.single.read<String>('payload')) as Map<String, dynamic>;
    return Account.restore(
      id: id,
      workspace: workspace,
      name: json['name'] as String,
      kind: AccountKind.values.byName(json['kind'] as String),
      currency: Currency(json['currency'] as String, json['scale'] as int),
      openedOn: BusinessDate.parse(json['openedOn'] as String),
      includeInNetWorth: json['includeInNetWorth'] as bool,
      version: json['version'] as int,
      state: AccountState.values.byName(json['state'] as String),
      closedOn: json['closedOn'] == null
          ? null
          : BusinessDate.parse(json['closedOn'] as String),
      closingReason: json['closingReason'] as String?,
      successorId: json['successorId'] == null
          ? null
          : PublicId.parse(json['successorId'] as String),
    );
  }

  Future<void> replace(Account account) => db.customStatement(
    'UPDATE accounts SET payload = ? WHERE workspace = ? AND id = ?',
    [
      jsonEncode(accountJson(account)),
      account.workspace.toString(),
      account.id.value,
    ],
  );
}

Map<String, Object?> accountJson(Account account) => {
  'name': account.name,
  'kind': account.kind.name,
  'currency': account.currency.code,
  'scale': account.currency.scale,
  'openedOn': account.openedOn.toString(),
  'includeInNetWorth': account.includeInNetWorth,
  'version': account.version,
  'state': account.state.name,
  'closedOn': account.closedOn?.toString(),
  'closingReason': account.closingReason,
  'successorId': account.successorId?.value,
};

final class LedgerAdapter {
  LedgerAdapter(this.db, {this.sourceContext = 'fixture-manual-v1'});
  final ProbeDatabase db;
  final String sourceContext;
  Future<void> insert(
    Posting posting, {
    void Function(String)? checkpoint,
  }) async {
    final ws = posting.operation.workspace.toString();
    await db.customStatement(
      'INSERT INTO events (workspace,id,kind,business_date,income,expense,currency,scale,source_context) VALUES (?,?,?,?,?,?,?,?,?)',
      [
        ws,
        posting.id.value,
        posting.kind.name,
        posting.date.toString(),
        posting.reportIncome.minorUnits.toInt(),
        posting.reportExpense.minorUnits.toInt(),
        posting.reportIncome.currency.code,
        posting.reportIncome.currency.scale,
        sourceContext,
      ],
    );
    checkpoint?.call('event');
    var ordinal = 0;
    for (final leg in posting.legs) {
      await db.customStatement('INSERT INTO legs VALUES (?,?,?,?,?,?,?,?)', [
        ws,
        posting.id.value,
        ordinal++,
        leg.account.id.value,
        leg.amount.minorUnits.toInt(),
        leg.amount.currency.code,
        leg.amount.currency.scale,
        leg.role.name,
      ]);
      checkpoint?.call('leg');
    }
    if (posting.kind == PostingKind.opening) {
      await db.customStatement('INSERT INTO openings VALUES (?,?,?)', [
        ws,
        posting.legs.single.account.id.value,
        posting.id.value,
      ]);
    }
    for (final allocation in posting.allocations) {
      await db.customStatement('INSERT INTO allocations VALUES (?,?,?,?)', [
        ws,
        posting.id.value,
        allocation.categoryId.value,
        allocation.amount.minorUnits.toInt(),
      ]);
    }
  }

  Future<Money> balance(PostingAccount account) async {
    final rows = await db
        .customSelect(
          'SELECT amount,currency,scale FROM legs WHERE workspace = ? AND account_id = ?',
          variables: [
            Variable.withString(account.workspace.toString()),
            Variable.withString(account.id.value),
          ],
        )
        .get();
    var total = BigInt.zero;
    for (final row in rows) {
      if (row.read<String>('currency') != account.currency.code ||
          row.read<int>('scale') != account.currency.scale) {
        throw const LedgerException(LedgerError.currencyMismatch);
      }
      total += BigInt.from(row.read<int>('amount'));
    }
    return Money(account.currency, total);
  }
}

/// Versioned fixture canonicalization excludes generated result IDs and clock.
Object postingInput(Posting posting) => [
  'posting-v1',
  posting.kind.name,
  posting.date.toString(),
  for (final leg in posting.legs)
    [
      leg.account.id.value,
      leg.account.expectedVersion,
      leg.amount.toJson(),
      leg.role.name,
    ],
  for (final allocation in posting.allocations)
    [allocation.categoryId.value, allocation.amount.toJson()],
];
