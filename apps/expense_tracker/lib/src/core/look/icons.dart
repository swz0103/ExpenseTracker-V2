import 'package:flutter/painting.dart';

import '../ledger/ledger.dart';
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

/// Marks an account may take, in groups by what the account is, each
/// with the name a screen reader says. None is a category's mark.
const accountIconGroups = [
  (
    '銀行與存款',
    [
      ('bank', '銀行'),
      ('passbook', '存摺'),
      ('vault', '金庫'),
      ('hourglass', '定存'),
      ('piggy', '存錢筒'),
      ('jar', '零錢罐'),
      ('envelope', '信封袋'),
      ('goldBar', '金條'),
    ],
  ),
  (
    '現金與支付',
    [
      ('cash', '現金'),
      ('bills', '鈔票堆'),
      ('wallet', '皮夾'),
      ('phonePay', '手機支付'),
      ('contactless', '感應卡'),
      ('scan', '掃碼'),
      ('watch', '手錶'),
      ('topUp', '儲值卡'),
    ],
  ),
  (
    '卡片與外幣',
    [
      ('chipCard', '信用卡'),
      ('twoCards', '多張卡'),
      ('globe', '外幣'),
      ('dollar', '美元'),
      ('yen', '日圓'),
      ('exchange', '換匯'),
      ('key', '鑰匙'),
      ('chest', '寶箱'),
    ],
  ),
  (
    '目標與心願',
    [
      ('diamond', '鑽石'),
      ('crown', '皇冠'),
      ('flag', '目標'),
      ('target', '靶心'),
      ('anchor', '預備金'),
      ('lifebuoy', '救生圈'),
      ('star', '星號'),
      ('sprout', '成長'),
    ],
  ),
];

/// The six marks offered first for an account of [kind]; the rest open
/// from 更多.
List<String> usualAccountIcons(AccountKind kind) => switch (kind) {
  AccountKind.bank => const [
    'bank',
    'passbook',
    'piggy',
    'hourglass',
    'vault',
    'globe',
  ],
  AccountKind.wallet => const [
    'phonePay',
    'contactless',
    'scan',
    'topUp',
    'watch',
    'wallet',
  ],
  AccountKind.cash => const [
    'cash',
    'wallet',
    'jar',
    'envelope',
    'bills',
    'piggy',
  ],
  AccountKind.card => const [
    'chipCard',
    'twoCards',
    'contactless',
    'star',
    'diamond',
    'crown',
  ],
  AccountKind.loan || AccountKind.receivable => const [],
};

/// The name a screen reader says for the account mark [key].
String accountIconName(String key) {
  for (final (_, marks) in accountIconGroups) {
    for (final (k, name) in marks) {
      if (k == key) return name;
    }
  }
  return key;
}

/// The marks accounts took before the set above, by the one each now
/// shows, so an account kept from then still has a mark of its own.
const _earlierAccountIcons = {
  'coins': Glyph.jar,
  'safe': Glyph.vault,
  'phone': Glyph.phonePay,
  'chat': Glyph.phonePay,
  'store': Glyph.topUp,
  'ticket': Glyph.contactless,
  'card': Glyph.chipCard,
  'suitcase': Glyph.chest,
  'briefcase': Glyph.passbook,
  'home': Glyph.key,
  'car': Glyph.key,
  'school': Glyph.flag,
  'heart': Glyph.piggy,
  'shield': Glyph.anchor,
  'gift': Glyph.chest,
  'investment': Glyph.goldBar,
};

/// The mark the account key [key] shows: its own, the one an earlier
/// key now stands for, or none when it is not known.
Glyph? accountMark(String key) {
  final earlier = _earlierAccountIcons[key];
  if (earlier != null) return earlier;
  for (final (_, marks) in accountIconGroups) {
    for (final (k, _) in marks) {
      if (k == key) return iconFor(k);
    }
  }
  return null;
}

/// The account's own mark, or its kind's.
Glyph accountIcon(Account account) {
  final key = account.icon;
  return (key == null ? null : accountMark(key)) ?? kindIcon(account.kind);
}

Glyph kindIcon(AccountKind kind) => switch (kind) {
  AccountKind.cash => Glyph.cash,
  AccountKind.bank => Glyph.bank,
  AccountKind.wallet => Glyph.phonePay,
  AccountKind.card => Glyph.chipCard,
  AccountKind.loan => Glyph.loan,
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
