import 'package:flutter/material.dart';

import '../demo/ledger.dart';
import 'theme.dart';

const _categoryIcons = {
  'home': Icons.home_outlined,
  'food': Icons.ramen_dining_outlined,
  'travel': Icons.directions_bus_outlined,
  'bag': Icons.shopping_bag_outlined,
  'subscription': Icons.event_note_outlined,
  'other': Icons.more_horiz,
  'salary': Icons.move_to_inbox_outlined,
  'dividend': Icons.savings_outlined,
  'income': Icons.inbox_outlined,
  'transfer': Icons.sync_alt,
  'investment': Icons.trending_up,
};

/// Icon keys a new category may take.
const categoryIconKeys = [
  'home',
  'food',
  'travel',
  'bag',
  'subscription',
  'other',
  'salary',
  'dividend',
  'income',
];

IconData iconFor(String key) => _categoryIcons[key] ?? Icons.more_horiz;

IconData accountIcon(AccountKind kind) => switch (kind) {
  AccountKind.cash => Icons.payments_outlined,
  AccountKind.bank => Icons.account_balance_outlined,
  AccountKind.wallet => Icons.phone_iphone_outlined,
  AccountKind.card => Icons.credit_card_outlined,
};

Color accountColor(AccountKind kind) => switch (kind) {
  AccountKind.cash => Hue.cash,
  AccountKind.bank => Hue.bank,
  AccountKind.wallet => Hue.wallet,
  AccountKind.card => Hue.card,
};

String groupName(AccountKind kind) => switch (kind) {
  AccountKind.cash => '現金',
  AccountKind.bank => '銀行帳戶',
  AccountKind.wallet => '電子支付',
  AccountKind.card => '信用卡',
};

/// The colour an entry's amount is written in.
Color entryColor(EntryType type) => switch (type) {
  EntryType.expense => Hue.negative,
  EntryType.income || EntryType.dividend || EntryType.sell => Hue.positive,
  EntryType.transfer => Hue.transfer,
  EntryType.buy => Hue.investment,
};
