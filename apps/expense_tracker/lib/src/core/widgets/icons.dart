import 'package:flutter/painting.dart';

import '../ledger/ledger.dart';
import '../design_system/glyphs.dart';
import '../design_system/theme.dart';
import '../formatting/words.dart';

/// Icon groups a category may take its mark from, by what it is for:
/// a hundred in all (`icons_test`), each with the name a screen reader
/// says.
const categoryIconGroups = [
  (
    '飲食',
    [
      ('food', '碗'),
      ('cup', '咖啡'),
      ('drink', '手搖飲'),
      ('cake', '蛋糕'),
      ('beer', '啤酒'),
      ('cart', '購物車'),
      ('apple', '蘋果'),
      ('burger', '漢堡'),
      ('pizza', '披薩'),
      ('rice', '飯糰'),
      ('icecream', '冰淇淋'),
      ('wine', '酒杯'),
      ('bread', '吐司'),
    ],
  ),
  (
    '交通',
    [
      ('travel', '公車'),
      ('bus', '遊覽車'),
      ('train', '火車'),
      ('bike', '腳踏車'),
      ('car', '汽車'),
      ('fuel', '加油'),
      ('parking', '停車'),
      ('plane', '飛機'),
      ('ship', '船'),
      ('scooter', '機車'),
      ('pin', '地點'),
      ('map', '地圖'),
    ],
  ),
  (
    '居家',
    [
      ('home', '房子'),
      ('bolt', '電'),
      ('water', '水'),
      ('wifi', '網路'),
      ('tool', '扳手'),
      ('bed', '床'),
      ('leaf', '葉子'),
      ('sofa', '沙發'),
      ('lamp', '檯燈'),
      ('washer', '洗衣機'),
      ('door', '門'),
      ('calendar', '日曆'),
    ],
  ),
  (
    '購物',
    [
      ('bag', '購物袋'),
      ('shirt', '衣服'),
      ('sparkle', '閃亮'),
      ('scissors', '剪刀'),
      ('gift', '禮物'),
      ('store', '商店'),
      ('glasses', '眼鏡'),
      ('shoe', '鞋子'),
      ('lipstick', '口紅'),
      ('jewel', '戒指'),
      ('perfume', '香水'),
      ('tag', Words.tag),
    ],
  ),
  (
    '娛樂',
    [
      ('game', '遊戲'),
      ('film', '電視'),
      ('music', '音樂'),
      ('camera', '相機'),
      ('ticket', '票券'),
      ('suitcase', '行李箱'),
      ('palette', '調色盤'),
      ('tent', '帳篷'),
      ('headphones', '耳機'),
      ('ball', '球'),
      ('image', '照片'),
    ],
  ),
  (
    '健康',
    [
      ('health', '健康'),
      ('pill', '藥丸'),
      ('fitness', '啞鈴'),
      ('baby', '奶瓶'),
      ('pet', '寵物'),
      ('tooth', '牙齒'),
      ('clinic', '醫療'),
    ],
  ),
  (
    '學習與工作',
    [
      ('book', '書'),
      ('school', '學士帽'),
      ('laptop', '筆電'),
      ('briefcase', '公事包'),
      ('phone', '手機'),
      ('pen', '筆'),
      ('calculator', '計算機'),
    ],
  ),
  (
    '人情',
    [
      ('chat', '對話'),
      ('bell', '鈴鐺'),
      ('flower', '花'),
      ('people', '朋友'),
      ('redPacket', '紅包'),
      ('balloon', '氣球'),
    ],
  ),
  (
    '金融',
    [
      ('subscription', '訂閱'),
      ('shield', '保險'),
      ('tax', '稅單'),
      ('card', '卡片'),
      ('coins', '硬幣'),
      ('safe', '保險箱'),
      ('heart', '愛心'),
      ('receipt', Words.receipt),
      ('percent', '折扣'),
    ],
  ),
  (
    Words.income,
    [
      ('salary', '薪水'),
      ('income', '錢袋'),
      ('dividend', Words.dividend),
      ('investment', Words.investment),
      ('trophy', '獎盃'),
      ('medal', '獎牌'),
    ],
  ),
  (
    '其他',
    [
      ('umbrella', '雨傘'),
      ('other', '其他'),
      ('sun', '太陽'),
      ('cloud', '雲'),
      ('parcel', '包裹'),
    ],
  ),
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

/// The name a screen reader says for the category mark [key].
String categoryIconName(String key) {
  for (final (_, marks) in categoryIconGroups) {
    for (final (k, name) in marks) {
      if (k == key) return name;
    }
  }
  return key;
}

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

/// [account]'s colour: the one picked for it, else its kind's.
Color accountColor(Account account) => switch (account.color) {
  final argb? => shownColor(Color(argb)),
  null => accountKindColor(account.kind),
};

Color accountKindColor(AccountKind kind) => switch (kind) {
  AccountKind.cash => AppColors.cash,
  AccountKind.bank => AppColors.bank,
  AccountKind.wallet => AppColors.wallet,
  AccountKind.card => AppColors.card,
  AccountKind.loan => AppColors.investment,
  AccountKind.receivable => AppColors.receivable,
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
  EntryType.expense => AppColors.negative,
  EntryType.income ||
  EntryType.dividend ||
  EntryType.sell => AppColors.positive,
  EntryType.transfer => AppColors.transfer,
  EntryType.buy => AppColors.investment,
};

/// [LoanRepay] as the form names it.
String repayName(LoanRepay repay) => switch (repay) {
  LoanRepay.even => '本息平均',
  LoanRepay.principal => '本金平均',
  LoanRepay.interest => '只繳息',
};
