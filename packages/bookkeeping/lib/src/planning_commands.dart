import 'dart:convert';

import 'package:app_core/app_core.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:recurring_transactions/recurring_transactions.dart';
import 'package:reports/reports.dart';

import 'commands.dart';

/// Creates or revises a monthly budget. Returns the plan's new version.
final class SetBudget implements Command<int> {
  SetBudget({
    required this.operation,
    required this.budgetId,
    required this.expectedVersion,
    required this.month,
    required this.limit,
    this.categoryId,
    this.accountIds = const {},
    this.tagIds = const {},
    this.warningPercent = 80,
    this.repeats = false,
  });

  @override
  final OperationKey operation;
  final PublicId budgetId;

  /// 0 for a new budget.
  final int expectedVersion;
  final ReportMonth month;
  final Money limit;
  final PublicId? categoryId;
  final Set<PublicId> accountIds;
  final Set<PublicId> tagIds;
  final int warningPercent;

  /// The budget applies to [month] and every later month.
  final bool repeats;

  @override
  String get input => jsonEncode({
    'command': 'set-budget-v1',
    'budgetId': budgetId.value,
    'expectedVersion': expectedVersion,
    'month': '${month.year}-${month.month}',
    'limit': limit.toJson(),
    'categoryId': categoryId?.value,
    'accountIds': ([for (final id in accountIds) id.value]..sort()),
    'tagIds': ([for (final id in tagIds) id.value]..sort()),
    'warningPercent': warningPercent,
    'repeats': repeats,
  });

  @override
  String encodeResult(int result) => '$result';

  @override
  int decodeResult(String encoded) => int.parse(encoded);
}

/// Creates, revises or stops a recurring template. A negative amount is an
/// expense, a positive one an income. Returns the template's new version.
final class SaveRecurring implements Command<int> {
  SaveRecurring({
    required this.operation,
    required this.templateId,
    required this.expectedVersion,
    required this.accountId,
    required this.label,
    required this.amount,
    required this.firstDate,
    required this.unit,
    required this.every,
    this.active = true,
    this.lastDate,
    this.categoryId,
    this.tagIds = const {},
    this.merchantId,
  });

  @override
  final OperationKey operation;
  final PublicId templateId;

  /// 0 for a new template.
  final int expectedVersion;
  final PublicId accountId;
  final String label;
  final Money amount;
  final BusinessDate firstDate;
  final RecurrenceUnit unit;
  final int every;

  /// False stops further proposals; confirmed postings stay.
  final bool active;

  /// The last day an occurrence may fall on; null runs on.
  final BusinessDate? lastDate;

  /// Defaults offered when an occurrence is confirmed.
  final PublicId? categoryId;
  final Set<PublicId> tagIds;
  final PublicId? merchantId;

  @override
  String get input => jsonEncode({
    'command': 'save-recurring-v1',
    'templateId': templateId.value,
    'expectedVersion': expectedVersion,
    'accountId': accountId.value,
    'label': label,
    'amount': amount.toJson(),
    'firstDate': firstDate.toString(),
    'unit': unit.name,
    'every': every,
    'active': active,
    'lastDate': lastDate?.toString(),
    'categoryId': categoryId?.value,
    'tagIds': [for (final id in tagIds) id.value]..sort(),
    'merchantId': merchantId?.value,
  });

  @override
  String encodeResult(int result) => '$result';

  @override
  int decodeResult(String encoded) => int.parse(encoded);
}

/// Records one proposed occurrence as a real posting. Each due date of a
/// template can be confirmed once. The amount, date and classification may
/// differ from the template, for example this month's electricity bill.
/// Returns the posting id.
final class ConfirmRecurring extends PostingCommand {
  ConfirmRecurring({
    required OperationKey operation,
    required PublicId postingId,
    required this.templateId,
    required this.expectedTemplateVersion,
    required this.dueDate,
    required this.account,
    this.amount,
    this.date,
    this.allocations = const [],
    this.tags = const [],
    this.merchant,
  }) : super(operation, postingId);

  final PublicId templateId;
  final int expectedTemplateVersion;
  final BusinessDate dueDate;
  final AccountRef account;

  /// The actual amount, positive; the template's when null.
  final Money? amount;

  /// The day it was paid; the due date when null.
  final BusinessDate? date;
  final List<CategoryShare> allocations;
  final List<TagSelection> tags;
  final MerchantSelection? merchant;

  @override
  Map<String, Object?> get fields => {
    'command': 'confirm-recurring-v1',
    'postingId': postingId.value,
    'templateId': templateId.value,
    'expectedTemplateVersion': expectedTemplateVersion,
    'dueDate': dueDate.toString(),
    'account': account.toJson(),
    'amount': amount?.toJson(),
    'date': date?.toString(),
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
