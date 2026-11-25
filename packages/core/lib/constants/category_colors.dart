/// The colours new categories take.
library;

/// The colours a category may be given (ARGB), in the order new ones take
/// them: the one list, which the app's screens offer to choose from
/// (`AppColors.categoryColors` is made from it) and which a category made
/// in 記一筆, 分類 or by an import takes its colour from
/// ([nextCategoryColor]), so the same category gets the same colour
/// however it is made (review 32, 2.3). Here, below both the app's
/// design system and its ledger, so each can read it.
const categoryColorValues = <int>[
  0xFF5B8DB0,
  0xFFD08B5B,
  0xFF5C9A83,
  0xFF8E7CC0,
  0xFFC9A34A,
  0xFFB07A8C,
  0xFF4E8A9A,
  0xFFA0866A,
  0xFF7686B8,
  0xFF9AA35E,
  0xFF6E9C93,
  0xFFB08AA6,
];

/// The colour a new category takes when the book already has [count]:
/// the colours in turn, starting over after the last.
int nextCategoryColor(int count) =>
    categoryColorValues[count % categoryColorValues.length];
