/// Numbers as a person types them on a Chinese keyboard: the one
/// normaliser of full-width forms, which a parser that takes them reads
/// through (the broker discount, D86). An amount does not: `parseAmount`
/// refuses full-width digits as not a number.
library;

/// The first and last full-width form of a printable ASCII character:
/// `！` (U+FF01) to `～` (U+FF5E), each U+FEE0 past its ASCII form.
const _firstFullWidth = 0xFF01;
const _lastFullWidth = 0xFF5E;
const _fullWidthOffset = 0xFEE0;

/// The ideographic space a Chinese keyboard types (U+3000).
const _ideographicSpace = 0x3000;
const _space = 0x20;

/// [text] with its full-width forms in ASCII: `１２．５` reads `12.5`,
/// `６折` reads `6折`, `－３００` reads `-300` and the ideographic space
/// a plain one. Everything else is left as it is.
String halfWidth(String text) => String.fromCharCodes([
  for (final c in text.runes)
    if (c >= _firstFullWidth && c <= _lastFullWidth)
      c - _fullWidthOffset
    else if (c == _ideographicSpace)
      _space
    else
      c,
]);
