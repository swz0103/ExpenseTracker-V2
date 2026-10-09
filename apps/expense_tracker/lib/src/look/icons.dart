import 'package:flutter/painting.dart';

import '../demo/ledger.dart';
import 'glyphs.dart';
import 'theme.dart';

const _categoryIcons = {
  'home': Glyph.home,
  'food': Glyph.food,
  'travel': Glyph.travel,
  'bag': Glyph.bag,
  'subscription': Glyph.subscription,
  'other': Glyph.other,
  'salary': Glyph.salary,
  'dividend': Glyph.dividend,
  'income': Glyph.income,
  'transfer': Glyph.transfer,
  'investment': Glyph.investment,
  'cup': Glyph.cup,
  'shirt': Glyph.shirt,
  'gift': Glyph.gift,
  'book': Glyph.book,
  'health': Glyph.health,
  'pet': Glyph.pet,
  'car': Glyph.car,
  'game': Glyph.game,
};

/// Icon keys a new category may take.
const categoryIconKeys = [
  'food',
  'cup',
  'home',
  'travel',
  'car',
  'bag',
  'shirt',
  'subscription',
  'game',
  'book',
  'health',
  'gift',
  'pet',
  'other',
  'salary',
  'income',
  'dividend',
];

Glyph iconFor(String key) => _categoryIcons[key] ?? Glyph.other;

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
