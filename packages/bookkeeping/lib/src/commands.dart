import 'dart:convert';

import 'package:accounts/accounts.dart';
import 'package:app_core/app_core.dart';
import 'package:foundation_values/foundation_values.dart';

/// Account commands return the account version after the change.
abstract base class AccountCommand implements Command<int> {
  AccountCommand(this.operation);

  @override
  final OperationKey operation;

  Map<String, Object?> get fields;

  @override
  String get input => jsonEncode(fields);

  @override
  String encodeResult(int result) => '$result';

  @override
  int decodeResult(String encoded) => int.parse(encoded);
}

/// Posting commands return the id of the posting they recorded.
abstract base class PostingCommand implements Command<PublicId> {
  PostingCommand(this.operation, this.postingId);

  @override
  final OperationKey operation;
  final PublicId postingId;

  Map<String, Object?> get fields;

  @override
  String get input => jsonEncode(fields);

  @override
  String encodeResult(PublicId result) => result.value;

  @override
  PublicId decodeResult(String encoded) => PublicId.parse(encoded);
}

final class OpenAccount extends AccountCommand {
  OpenAccount({
    required OperationKey operation,
    required this.accountId,
    required this.name,
    required this.kind,
    required this.currency,
    required this.openedOn,
    this.includeInNetWorth = true,
    this.openingBalance,
    this.openingPostingId,
  }) : super(operation) {
    if ((openingBalance == null) != (openingPostingId == null)) {
      throw ArgumentError('Opening balance needs exactly one posting id.');
    }
  }

  final PublicId accountId;
  final String name;
  final AccountKind kind;
  final Currency currency;
  final BusinessDate openedOn;
  final bool includeInNetWorth;
  final Money? openingBalance;
  final PublicId? openingPostingId;

  @override
  Map<String, Object?> get fields => {
    'command': 'open-account-v1',
    'accountId': accountId.value,
    'name': name,
    'kind': kind.name,
    'currency': currency.code,
    'scale': currency.scale,
    'openedOn': openedOn.toString(),
    'includeInNetWorth': includeInNetWorth,
    'openingBalance': openingBalance?.toJson(),
    'openingPostingId': openingPostingId?.value,
  };
}

final class RenameAccount extends AccountCommand {
  RenameAccount({
    required OperationKey operation,
    required this.accountId,
    required this.expectedVersion,
    required this.name,
  }) : super(operation);

  final PublicId accountId;
  final int expectedVersion;
  final String name;

  @override
  Map<String, Object?> get fields => {
    'command': 'rename-account-v1',
    'accountId': accountId.value,
    'expectedVersion': expectedVersion,
    'name': name,
  };
}

enum AccountStateChange { archive, reactivate }

final class ChangeAccountState extends AccountCommand {
  ChangeAccountState({
    required OperationKey operation,
    required this.accountId,
    required this.expectedVersion,
    required this.change,
  }) : super(operation);

  final PublicId accountId;
  final int expectedVersion;
  final AccountStateChange change;

  @override
  Map<String, Object?> get fields => {
    'command': 'change-account-state-v1',
    'accountId': accountId.value,
    'expectedVersion': expectedVersion,
    'change': change.name,
  };
}

/// The account a posting touches, with the version the person saw.
final class AccountRef {
  const AccountRef(this.id, this.expectedVersion);

  final PublicId id;
  final int expectedVersion;

  Map<String, Object?> toJson() => {
    'id': id.value,
    'expectedVersion': expectedVersion,
  };
}

enum CashFlow { income, expense }

final class RecordCashFlow extends PostingCommand {
  RecordCashFlow({
    required OperationKey operation,
    required PublicId postingId,
    required this.flow,
    required this.account,
    required this.date,
    required this.amount,
  }) : super(operation, postingId);

  final CashFlow flow;
  final AccountRef account;
  final BusinessDate date;
  final Money amount;

  @override
  Map<String, Object?> get fields => {
    'command': 'record-cash-flow-v1',
    'postingId': postingId.value,
    'flow': flow.name,
    'account': account.toJson(),
    'date': date.toString(),
    'amount': amount.toJson(),
  };
}

final class RecordTransfer extends PostingCommand {
  RecordTransfer({
    required OperationKey operation,
    required PublicId postingId,
    required this.source,
    required this.destination,
    required this.date,
    required this.principal,
    this.received,
    this.fee,
  }) : super(operation, postingId);

  final AccountRef source;
  final AccountRef destination;
  final BusinessDate date;
  final Money principal;
  final Money? received;
  final Money? fee;

  @override
  Map<String, Object?> get fields => {
    'command': 'record-transfer-v1',
    'postingId': postingId.value,
    'source': source.toJson(),
    'destination': destination.toJson(),
    'date': date.toString(),
    'principal': principal.toJson(),
    'received': received?.toJson(),
    'fee': fee?.toJson(),
  };
}

/// Corrects a posting by appending its exact negation. The original stays in
/// the journal; the reversal has its own effective date.
final class ReversePosting extends PostingCommand {
  ReversePosting({
    required OperationKey operation,
    required PublicId reversalId,
    required this.originalId,
    required this.date,
    this.reason = '',
  }) : super(operation, reversalId);

  final PublicId originalId;
  final BusinessDate date;
  final String reason;

  @override
  Map<String, Object?> get fields => {
    'command': 'reverse-posting-v1',
    'postingId': postingId.value,
    'originalId': originalId.value,
    'date': date.toString(),
    'reason': reason,
  };
}
