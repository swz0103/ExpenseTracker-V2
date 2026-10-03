import 'package:accounts/accounts.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

/// Thrown when stored JSON does not decode to a valid domain object.
final class CodecException implements Exception {
  const CodecException(this.message);

  final String message;

  @override
  String toString() => 'CodecException($message)';
}

/// Versioned JSON for [Account]. Decoding goes through [Account.restore], so
/// stored state is validated exactly like any other input.
abstract final class AccountCodec {
  static const version = 1;

  static Map<String, Object?> encode(Account account) => {
    'version': version,
    'id': account.id.value,
    'workspace': account.workspace.toString(),
    'name': account.name,
    'kind': account.kind.name,
    'currency': _currency(account.currency),
    'openedOn': account.openedOn.toString(),
    'includeInNetWorth': account.includeInNetWorth,
    'accountVersion': account.version,
    'state': account.state.name,
    'closedOn': account.closedOn?.toString(),
    'closingReason': account.closingReason,
    'successorId': account.successorId?.value,
  };

  static Account decode(Map<String, Object?> json) => _decoding(() {
    _keys(json, const {
      'version',
      'id',
      'workspace',
      'name',
      'kind',
      'currency',
      'openedOn',
      'includeInNetWorth',
      'accountVersion',
      'state',
      'closedOn',
      'closingReason',
      'successorId',
    });
    if (json['version'] != version) throw const CodecException('version');
    final closedOn = json['closedOn'] as String?;
    final successor = json['successorId'] as String?;
    return Account.restore(
      id: PublicId.parse(json['id'] as String),
      workspace: WorkspaceId.parse(json['workspace'] as String),
      name: json['name'] as String,
      kind: AccountKind.values.byName(json['kind'] as String),
      currency: _readCurrency(json['currency']),
      openedOn: BusinessDate.parse(json['openedOn'] as String),
      includeInNetWorth: json['includeInNetWorth'] as bool,
      version: json['accountVersion'] as int,
      state: AccountState.values.byName(json['state'] as String),
      closedOn: closedOn == null ? null : BusinessDate.parse(closedOn),
      closingReason: json['closingReason'] as String?,
      successorId: successor == null ? null : PublicId.parse(successor),
    );
  });
}

/// Versioned JSON for the posting kinds bookkeeping records. Decoding
/// rebuilds the posting through its factory, so every ledger rule runs again.
abstract final class PostingCodec {
  static const version = 1;

  static const supported = {
    PostingKind.opening,
    PostingKind.income,
    PostingKind.expense,
    PostingKind.transfer,
    PostingKind.reversal,
  };

  static Map<String, Object?> encode(Posting posting) {
    if (!supported.contains(posting.kind) || posting.allocations.isNotEmpty) {
      throw UnsupportedError('Posting kind ${posting.kind.name} not stored.');
    }
    final base = <String, Object?>{
      'version': version,
      'id': posting.id.value,
      'workspace': posting.operation.workspace.toString(),
      'operation': posting.operation.operation.toString(),
      'date': posting.date.toString(),
      'kind': posting.kind.name,
    };
    final legs = posting.legs;
    switch (posting.kind) {
      case PostingKind.opening || PostingKind.income:
        return {
          ...base,
          'account': _account(legs.single.account),
          'amount': legs.single.amount.toJson(),
        };
      case PostingKind.expense:
        return {
          ...base,
          'account': _account(legs.single.account),
          'amount': (-legs.single.amount).toJson(),
        };
      case PostingKind.transfer:
        final fee = legs.where((leg) => leg.role == LegRole.fee);
        return {
          ...base,
          'source': _account(legs[0].account),
          'destination': _account(legs[1].account),
          'principal': (-legs[0].amount).toJson(),
          'received': legs[1].amount.toJson(),
          'fee': fee.isEmpty ? null : (-fee.single.amount).toJson(),
        };
      case PostingKind.reversal:
        return {
          ...base,
          'original': encode(posting.reversedPosting!),
          'reason': posting.reversalReason,
        };
      default:
        throw StateError('unreachable');
    }
  }

  static Posting decode(Map<String, Object?> json) => _decoding(() {
    if (json['version'] != version) throw const CodecException('version');
    final kind = PostingKind.values.byName(json['kind'] as String);
    final common = {'version', 'id', 'workspace', 'operation', 'date', 'kind'};
    final workspace = WorkspaceId.parse(json['workspace'] as String);
    final id = PublicId.parse(json['id'] as String);
    final operation = OperationKey(
      workspace,
      OperationId.parse(json['operation'] as String),
    );
    final date = BusinessDate.parse(json['date'] as String);
    switch (kind) {
      case PostingKind.opening ||
          PostingKind.income ||
          PostingKind.expense:
        _keys(json, {...common, 'account', 'amount'});
        final amount = _money(json['amount']);
        final account = _readAccount(json['account'], workspace, amount);
        return switch (kind) {
          PostingKind.opening => Posting.opening(
            id: id,
            operation: operation,
            date: date,
            account: account,
            amount: amount,
          ),
          PostingKind.income => Posting.income(
            id: id,
            operation: operation,
            date: date,
            account: account,
            amount: amount,
          ),
          _ => Posting.expense(
            id: id,
            operation: operation,
            date: date,
            account: account,
            amount: amount,
          ),
        };
      case PostingKind.transfer:
        _keys(json, {
          ...common,
          'source',
          'destination',
          'principal',
          'received',
          'fee',
        });
        final principal = _money(json['principal']);
        final received = _money(json['received']);
        final fee = json['fee'] == null ? null : _money(json['fee']);
        return Posting.transfer(
          id: id,
          operation: operation,
          date: date,
          source: _readAccount(json['source'], workspace, principal),
          destination: _readAccount(json['destination'], workspace, received),
          principal: principal,
          received: received,
          fee: fee,
        );
      case PostingKind.reversal:
        _keys(json, {...common, 'original', 'reason'});
        final original = json['original'];
        if (original is! Map<String, Object?> ||
            original['kind'] == PostingKind.reversal.name) {
          throw const CodecException('original');
        }
        return Posting.reversal(
          id: id,
          operation: operation,
          date: date,
          original: decode(original),
          reason: json['reason'] as String,
        );
      default:
        throw const CodecException('kind');
    }
  });

  static Map<String, Object?> _account(PostingAccount account) => {
    'id': account.id.value,
    'version': account.expectedVersion,
  };

  static PostingAccount _readAccount(
    Object? value,
    WorkspaceId workspace,
    Money amount,
  ) {
    if (value is! Map<String, Object?>) throw const CodecException('account');
    _keys(value, const {'id', 'version'});
    return PostingAccount(
      id: PublicId.parse(value['id'] as String),
      workspace: workspace,
      currency: amount.currency,
      expectedVersion: value['version'] as int,
    );
  }

  static Money _money(Object? value) {
    if (value is! Map<String, Object?>) throw const CodecException('money');
    return Money.fromJson(value);
  }
}

Map<String, Object?> _currency(Currency currency) => {
  'code': currency.code,
  'scale': currency.scale,
};

Currency _readCurrency(Object? value) {
  if (value is! Map<String, Object?>) throw const CodecException('currency');
  _keys(value, const {'code', 'scale'});
  return Currency(value['code'] as String, value['scale'] as int);
}

void _keys(Map<String, Object?> json, Set<String> keys) {
  if (json.length != keys.length || !keys.containsAll(json.keys)) {
    throw const CodecException('fields');
  }
}

/// Maps every decoding failure, including domain validation, to one type.
T _decoding<T>(T Function() body) {
  try {
    return body();
  } on CodecException {
    rethrow;
  } on Object catch (error) {
    throw CodecException(error.runtimeType.toString());
  }
}
