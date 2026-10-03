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

  static Account decode(Map<String, Object?> json) => decoding(() {
    checkKeys(json, const {
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
    PostingKind.investmentBuy,
    PostingKind.investmentSell,
    PostingKind.investmentDividend,
  };

  static Map<String, Object?> encode(Posting posting) {
    if (!supported.contains(posting.kind)) {
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
      case PostingKind.opening:
        return {
          ...base,
          'account': _account(legs.single.account),
          'amount': legs.single.amount.toJson(),
        };
      case PostingKind.income:
        return {
          ...base,
          'account': _account(legs.single.account),
          'amount': legs.single.amount.toJson(),
          'allocations': _allocations(posting.allocations),
        };
      case PostingKind.expense:
        return {
          ...base,
          'account': _account(legs.single.account),
          'amount': (-legs.single.amount).toJson(),
          'allocations': _allocations(posting.allocations),
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
      case PostingKind.investmentBuy:
        final buy = posting.investmentBuy!;
        return {
          ...base,
          'account': _account(legs.single.account),
          'tradeId': buy.buyId.value,
          'gross': buy.gross.toJson(),
          'fee': buy.fee.toJson(),
          'tax': buy.tax.toJson(),
          'cash': buy.cashDebit.toJson(),
        };
      case PostingKind.investmentSell:
        final sell = posting.investmentSell!;
        return {
          ...base,
          'account': _account(legs.single.account),
          'tradeId': sell.sellId.value,
          'gross': sell.gross.toJson(),
          'fee': sell.fee.toJson(),
          'tax': sell.tax.toJson(),
          'cash': sell.cashCredit.toJson(),
        };
      case PostingKind.investmentDividend:
        final dividend = posting.investmentDividend!;
        return {
          ...base,
          'account': _account(legs.single.account),
          'tradeId': dividend.dividendId.value,
          'gross': dividend.gross.toJson(),
          'fee': dividend.fee.toJson(),
          'tax': dividend.withholdingTax.toJson(),
          'cash': dividend.cashCredit.toJson(),
        };
      default:
        throw StateError('unreachable');
    }
  }

  static Posting decode(Map<String, Object?> json) => decoding(() {
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
      case PostingKind.opening:
        checkKeys(json, {...common, 'account', 'amount'});
        final amount = _money(json['amount']);
        return Posting.opening(
          id: id,
          operation: operation,
          date: date,
          account: _readAccount(json['account'], workspace, amount),
          amount: amount,
        );
      case PostingKind.income || PostingKind.expense:
        checkKeys(json, {...common, 'account', 'amount', 'allocations'});
        final amount = _money(json['amount']);
        final account = _readAccount(json['account'], workspace, amount);
        final allocations = _readAllocations(json['allocations']);
        return kind == PostingKind.income
            ? Posting.income(
                id: id,
                operation: operation,
                date: date,
                account: account,
                amount: amount,
                allocations: allocations,
              )
            : Posting.expense(
                id: id,
                operation: operation,
                date: date,
                account: account,
                amount: amount,
                allocations: allocations,
              );
      case PostingKind.transfer:
        checkKeys(json, {
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
        checkKeys(json, {...common, 'original', 'reason'});
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
      case PostingKind.investmentBuy ||
          PostingKind.investmentSell ||
          PostingKind.investmentDividend:
        checkKeys(json, {
          ...common,
          'account',
          'tradeId',
          'gross',
          'fee',
          'tax',
          'cash',
        });
        final cash = _money(json['cash']);
        final account = _readAccount(json['account'], workspace, cash);
        final trade = PublicId.parse(json['tradeId'] as String);
        final gross = _money(json['gross']);
        final fee = _money(json['fee']);
        final tax = _money(json['tax']);
        return switch (kind) {
          PostingKind.investmentBuy => Posting.investmentBuy(
            id: id,
            operation: operation,
            date: date,
            account: account,
            investmentBuyId: trade,
            gross: gross,
            fee: fee,
            tax: tax,
            cashDebit: cash,
          ),
          PostingKind.investmentSell => Posting.investmentSell(
            id: id,
            operation: operation,
            date: date,
            account: account,
            investmentSellId: trade,
            gross: gross,
            fee: fee,
            tax: tax,
            cashCredit: cash,
          ),
          _ => Posting.investmentDividend(
            id: id,
            operation: operation,
            date: date,
            account: account,
            investmentDividendId: trade,
            gross: gross,
            withholdingTax: tax,
            fee: fee,
            cashCredit: cash,
          ),
        };
      default:
        throw const CodecException('kind');
    }
  });

  static List<Map<String, Object?>> _allocations(List<Allocation> list) => [
    for (final allocation in list)
      {
        'categoryId': allocation.categoryId.value,
        'categoryVersion': allocation.expectedCategoryVersion,
        'amount': allocation.amount.toJson(),
      },
  ];

  static List<Allocation> _readAllocations(Object? value) {
    if (value is! List || value.length > 64) {
      throw const CodecException('allocations');
    }
    return [
      for (final item in value)
        if (item is Map<String, Object?>)
          _readAllocation(item)
        else
          throw const CodecException('allocation'),
    ];
  }

  static Allocation _readAllocation(Map<String, Object?> json) {
    checkKeys(json, const {'categoryId', 'categoryVersion', 'amount'});
    return Allocation(
      PublicId.parse(json['categoryId'] as String),
      _money(json['amount']),
      expectedCategoryVersion: json['categoryVersion'] as int?,
    );
  }

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
    checkKeys(value, const {'id', 'version'});
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
  checkKeys(value, const {'code', 'scale'});
  return Currency(value['code'] as String, value['scale'] as int);
}

void checkKeys(Map<String, Object?> json, Set<String> keys) {
  if (json.length != keys.length || !keys.containsAll(json.keys)) {
    throw const CodecException('fields');
  }
}

/// Maps every decoding failure, including domain validation, to one type.
T decoding<T>(T Function() body) {
  try {
    return body();
  } on CodecException {
    rethrow;
  } on Object catch (error) {
    throw CodecException(error.runtimeType.toString());
  }
}
