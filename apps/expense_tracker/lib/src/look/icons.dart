import 'package:flutter/painting.dart';

import '../model/ledger.dart';
import 'glyphs.dart';
import 'theme.dart';

/// Icon groups a category may take its mark from, by what it is for.
const categoryIconGroups = [
  ('飲食', ['food', 'cup', 'drink', 'cake', 'beer', 'cart']),
  ('交通', ['travel', 'bus', 'train', 'bike', 'car', 'fuel', 'parking', 'plane']),
  ('居家', ['home', 'bolt', 'water', 'wifi', 'tool', 'bed', 'leaf']),
  ('購物', ['bag', 'shirt', 'sparkle', 'scissors', 'gift', 'store']),
  ('娛樂', ['game', 'film', 'music', 'camera', 'ticket', 'suitcase']),
  ('健康', ['health', 'pill', 'fitness', 'baby', 'pet']),
  ('學習與工作', ['book', 'school', 'laptop', 'briefcase', 'phone']),
  ('金融', ['subscription', 'shield', 'tax', 'card', 'coins', 'safe', 'heart']),
  ('收入', ['salary', 'income', 'dividend', 'investment']),
  ('其他', ['umbrella', 'other']),
];

Glyph iconFor(String key) {
  for (final glyph in Glyph.values) {
    if (glyph.name == key) return glyph;
  }
  return Glyph.other;
}

/// Marks an account may take.
const accountIconKeys = [
  'cash',
  'coins',
  'bank',
  'safe',
  'phone',
  'chat',
  'store',
  'scan',
  'ticket',
  'card',
  'wallet',
  'suitcase',
  'briefcase',
  'home',
  'car',
  'school',
  'heart',
  'shield',
  'gift',
  'investment',
];

/// The account's own mark, or its kind's.
Glyph accountIcon(Account account) {
  final key = account.icon;
  return key == null ? kindIcon(account.kind) : iconFor(key);
}

Glyph kindIcon(AccountKind kind) => switch (kind) {
  AccountKind.cash => Glyph.cash,
  AccountKind.bank => Glyph.bank,
  AccountKind.wallet => Glyph.phone,
  AccountKind.card => Glyph.card,
  AccountKind.loan => Glyph.home,
  AccountKind.receivable => Glyph.heart,
};

Color accountColor(AccountKind kind) => switch (kind) {
  AccountKind.cash => Hue.cash,
  AccountKind.bank => Hue.bank,
  AccountKind.wallet => Hue.wallet,
  AccountKind.card => Hue.card,
  AccountKind.loan => Hue.investment,
  AccountKind.receivable => Hue.receivable,
};

String groupName(AccountKind kind) => switch (kind) {
  AccountKind.cash => '現金',
  AccountKind.bank => '銀行帳戶',
  AccountKind.wallet => '電子支付',
  AccountKind.card => '信用卡',
  AccountKind.loan => '貸款',
  AccountKind.receivable => '代墊與應收',
};

/// The colour an entry's amount is written in.
Color entryColor(EntryType type) => switch (type) {
  EntryType.expense => Hue.negative,
  EntryType.income || EntryType.dividend || EntryType.sell => Hue.positive,
  EntryType.transfer => Hue.transfer,
  EntryType.buy => Hue.investment,
};
