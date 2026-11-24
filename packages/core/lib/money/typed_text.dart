/// Text as a person types it or a file brings it: the one place it is
/// made plain. Numbers typed on a Chinese keyboard: the one normaliser
/// of full-width forms ([halfWidth]), which a parser that takes them
/// reads through (the broker discount, D86); an amount does not:
/// `parseAmount` refuses full-width digits as not a number. Words read
/// from outside the app: control characters and invisible marks taken
/// out ([plainText]).
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

/// [text] without what cannot be seen or kept as words: the control
/// characters (NUL and the rest of C0, DEL and C1) but tab, line feed
/// and carriage return; the invisible marks a copy from the web brings
/// along (zero-width space U+200B, non-joiner U+200C, the direction
/// marks U+200E and U+200F, word joiner U+2060, byte order mark
/// U+FEFF); and half of a surrogate pair alone. `現金` and a zero-width
/// space read `現金`, so a name read from a file is the name the book
/// has. The zero-width joiner stays: emoji are made with it.
String plainText(String text) => String.fromCharCodes([
  for (final c in text.runes)
    if (!_unseen(c)) c,
]);

bool _unseen(int c) =>
    (c < _space && c != _tab && c != _lineFeed && c != _carriageReturn) ||
    (c >= _delete && c < _firstPrintableLatin) ||
    _invisible.contains(c) ||
    (c >= _firstSurrogate && c <= _lastSurrogate);

const _tab = 0x09;
const _lineFeed = 0x0A;
const _carriageReturn = 0x0D;

/// DEL (U+007F), then the C1 controls up to U+009F.
const _delete = 0x7F;
const _firstPrintableLatin = 0xA0;

/// A surrogate's code unit, found alone by [String.runes].
const _firstSurrogate = 0xD800;
const _lastSurrogate = 0xDFFF;

const _invisible = {0x200B, 0x200C, 0x200E, 0x200F, 0x2060, 0xFEFF};
