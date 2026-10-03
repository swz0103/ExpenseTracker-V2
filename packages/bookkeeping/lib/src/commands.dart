import 'dart:convert';

import 'package:accounts/accounts.dart';
import 'package:app_core/app_core.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

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

/// Part of an income or expense attributed to one category.
final class CategoryShare {
  const CategoryShare(this.categoryId, this.expectedVersion, this.amount);

  final PublicId categoryId;
  final int expectedVersion;
  final Money amount;

  Map<String, Object?> toJson() => {
    'categoryId': categoryId.value,
    'expectedVersion': expectedVersion,
    'amount': amount.toJson(),
  };
}

final class RecordCashFlow extends PostingCommand {
  RecordCashFlow({
    required OperationKey operation,
    required PublicId postingId,
    required this.flow,
    required this.account,
    required this.date,
    required this.amount,
    this.allocations = const [],
    this.tags = const [],
    this.merchant,
  }) : super(operation, postingId);

  final CashFlow flow;
  final AccountRef account;
  final BusinessDate date;
  final Money amount;

  /// Empty, or shares that add up to [amount] exactly.
  final List<CategoryShare> allocations;
  final List<TagSelection> tags;
  final MerchantSelection? merchant;

  @override
  Map<String, Object?> get fields => {
    'command': 'record-cash-flow-v1',
    'postingId': postingId.value,
    'flow': flow.name,
    'account': account.toJson(),
    'date': date.toString(),
    'amount': amount.toJson(),
    'allocations': [for (final share in allocations) share.toJson()],
    'tags': [
      for (final tag in tags)
        {'id': tag.id.value, 'expectedVersion': tag.expectedVersion},
    ]..sort((a, b) => '${a['id']}'.compareTo('${b['id']}')),
    'merchant': merchant == null
        ? null
        : {
            'id': merchant!.id.value,
            'expectedVersion': merchant!.expectedVersion,
          },
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

/// Money returned for an earlier expense. [amount] is in the expense's
/// currency and counts against what is left to refund; [received] is the
/// cash that arrived when it differs in currency.
final class RecordRefund extends PostingCommand {
  RecordRefund({
    required OperationKey operation,
    required PublicId postingId,
    required this.originalId,
    required this.account,
    required this.date,
    required this.amount,
    this.received,
    this.allocations = const [],
  }) : super(operation, postingId);

  final PublicId originalId;
  final AccountRef account;
  final BusinessDate date;
  final Money amount;
  final Money? received;

  /// Required when the expense had categories: how much of each comes back.
  final List<CategoryShare> allocations;

  @override
  Map<String, Object?> get fields => {
    'command': 'record-refund-v1',
    'postingId': postingId.value,
    'originalId': originalId.value,
    'account': account.toJson(),
    'date': date.toString(),
    'amount': amount.toJson(),
    'received': received?.toJson(),
    'allocations': [for (final share in allocations) share.toJson()],
  };
}

/// Closes an account whose balance is zero and has nothing pending.
final class CloseAccount extends AccountCommand {
  CloseAccount({
    required OperationKey operation,
    required this.accountId,
    required this.expectedVersion,
    required this.date,
    required this.reason,
    this.successorId,
  }) : super(operation);

  final PublicId accountId;
  final int expectedVersion;
  final BusinessDate date;
  final String reason;
  final PublicId? successorId;

  @override
  Map<String, Object?> get fields => {
    'command': 'close-account-v1',
    'accountId': accountId.value,
    'expectedVersion': expectedVersion,
    'date': date.toString(),
    'reason': reason,
    'successorId': successorId?.value,
  };
}

/// Replaces an account's opening balance. Returns the new opening posting.
final class SetOpeningBalance extends PostingCommand {
  SetOpeningBalance({
    required OperationKey operation,
    required PublicId postingId,
    required this.reversalId,
    required this.accountId,
    required this.expectedVersion,
    required this.amount,
  }) : super(operation, postingId);

  /// Used only when an earlier opening has to be reversed.
  final PublicId reversalId;
  final PublicId accountId;
  final int expectedVersion;
  final Money amount;

  @override
  Map<String, Object?> get fields => {
    'command': 'set-opening-balance-v1',
    'postingId': postingId.value,
    'reversalId': reversalId.value,
    'accountId': accountId.value,
    'expectedVersion': expectedVersion,
    'amount': amount.toJson(),
  };
}

/// Sets the note on a posting. Returns the note's new revision; revision 0
/// means the posting never had a note.
final class SetNote extends AccountCommand {
  SetNote({
    required OperationKey operation,
    required this.postingId,
    required this.expectedRevision,
    required this.text,
  }) : super(operation);

  final PublicId postingId;
  final int expectedRevision;
  final String text;

  @override
  Map<String, Object?> get fields => {
    'command': 'set-note-v1',
    'postingId': postingId.value,
    'expectedRevision': expectedRevision,
    'text': text,
  };
}

/// Fixes an income or expense: the original is reversed on its own date
/// and a replacement is recorded, in one transaction, so reports for the
/// original month are corrected rather than offset in a later month.
/// Returns the replacement posting's id.
final class CorrectCashFlow extends PostingCommand {
  CorrectCashFlow({
    required OperationKey operation,
    required PublicId replacementId,
    required this.originalId,
    required this.reversalId,
    required this.account,
    required this.date,
    required this.amount,
    this.allocations = const [],
    this.tags = const [],
    this.merchant,
    this.reason = '',
  }) : super(operation, replacementId);

  final PublicId originalId;
  final PublicId reversalId;
  final AccountRef account;
  final BusinessDate date;
  final Money amount;
  final List<CategoryShare> allocations;
  final List<TagSelection> tags;
  final MerchantSelection? merchant;
  final String reason;

  @override
  Map<String, Object?> get fields => {
    'command': 'correct-cash-flow-v1',
    'replacementId': postingId.value,
    'originalId': originalId.value,
    'reversalId': reversalId.value,
    'account': account.toJson(),
    'date': date.toString(),
    'amount': amount.toJson(),
    'allocations': [for (final share in allocations) share.toJson()],
    'tags': [
      for (final tag in tags)
        {'id': tag.id.value, 'expectedVersion': tag.expectedVersion},
    ]..sort((a, b) => '${a['id']}'.compareTo('${b['id']}')),
    'merchant': merchant == null
        ? null
        : {
            'id': merchant!.id.value,
            'expectedVersion': merchant!.expectedVersion,
          },
    'reason': reason,
  };
}

/// Removes a posting from balances and reports by reversing it on its own
/// date. The original and the reversal stay in the journal.
final class DeletePosting extends PostingCommand {
  DeletePosting({
    required OperationKey operation,
    required PublicId reversalId,
    required this.originalId,
    this.reason = '',
  }) : super(operation, reversalId);

  final PublicId originalId;
  final String reason;

  @override
  Map<String, Object?> get fields => {
    'command': 'delete-posting-v1',
    'reversalId': postingId.value,
    'originalId': originalId.value,
    'reason': reason,
  };
}
