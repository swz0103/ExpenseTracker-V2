import 'package:flutter/painting.dart';

import '../demo/ledger.dart';
import 'glyphs.dart';
import 'theme.dart';

/// Icon groups a category may take its mark from, by what it is for.
const categoryIconGroups = [
  ('飲食', ['food', 'cup', 'drink', 'cart']),
  ('交通', ['travel', 'train', 'car', 'fuel', 'parking', 'plane']),
  ('居家', ['home', 'bolt', 'water', 'wifi', 'tool', 'bed']),
  ('購物', ['bag', 'shirt', 'sparkle', 'gift', 'store']),
  ('娛樂', ['game', 'film', 'music', 'ticket', 'suitcase']),
  ('健康', ['health', 'pill', 'fitness', 'baby', 'pet']),
  ('學習與工作', ['book', 'school', 'briefcase', 'phone']),
  ('金融', ['subscription', 'shield', 'card', 'coins', 'safe', 'heart']),
  ('收入', ['salary', 'income', 'dividend', 'investment']),
  ('其他', ['other']),
];

/// Every icon key a category may take.
List<String> get categoryIconKeys => [
  for (final (_, keys) in categoryIconGroups) ...keys,
];

Glyph iconFor(String key) {
  for (final glyph in Glyph.values) {
    if (glyph.name == key) return glyph;
  }
  return Glyph.other;
}

const _accountIcons = {
  'phone': Glyph.phone,
  'safe': Glyph.safe,
  'suitcase': Glyph.suitcase,
  'briefcase': Glyph.briefcase,
  'chat': Glyph.chat,
  'store': Glyph.store,
  'scan': Glyph.scan,
  'ticket': Glyph.ticket,
  'coins': Glyph.coins,
};

/// The account's own mark, or its kind's.
Glyph accountIcon(Account account) =>
    _accountIcons[account.icon] ?? kindIcon(account.kind);

Glyph kindIcon(AccountKind kind) => switch (kind) {
  AccountKind.cash => Glyph.cash,
  AccountKind.bank => Glyph.bank,
  AccountKind.wallet => Glyph.phone,
  AccountKind.card => Glyph.card,
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
