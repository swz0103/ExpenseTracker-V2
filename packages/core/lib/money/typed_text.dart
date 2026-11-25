/// Text as a person types it or a file brings it: the one place it is
/// made plain. Numbers typed on a Chinese keyboard: the one normaliser
/// of full-width forms ([halfWidth]), which a parser that takes them
/// reads through (the broker discount, D86); an amount does not:
/// `parseAmount` refuses full-width digits as not a number. Words read
/// from outside the app: control characters and invisible marks taken
/// out ([plainText]). Words a search compares: [searchKey].
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

/// [text] as a search compares it: full-width forms in ASCII
/// ([halfWidth]), letters in lower case, 臺 written 台, and no spaces at
/// all, so `ＧＯＯＧＬＥ`, `google` and `Goo gle` find the same, and `臺灣`
/// finds `台灣`. Both what is typed and what is looked through are read
/// through it.
String searchKey(String text) =>
    halfWidth(text)
        .toLowerCase()
        .replaceAll(_variantTai, _tai)
        .replaceAll(_spaces, '');

/// 臺 (U+81FA) and the 台 (U+53F0) everyday writing uses for it.
const _variantTai = '臺';
const _tai = '台';

/// Any white space, the ideographic space made plain before.
final _spaces = RegExp(r'\s+');

/// [text] without what cannot be seen or kept as words: the control
/// characters (NUL and the rest of C0, DEL and C1) but tab, line feed
/// and carriage return; the invisible marks a copy from the web brings
/// along (zero-width space U+200B, non-joiner U+200C, the direction
/// marks U+200E and U+200F, word joiner U+2060, byte order mark
/// U+FEFF); the controls that turn the direction text is shown in,
/// with which a name can be made to read as another (embeddings and
/// overrides U+202A to U+202E, isolates U+2066 to U+2069, r13 F4); the
/// line and paragraph separators U+2028 and U+2029; the soft hyphen
/// U+00AD and the Mongolian vowel separator U+180E; and half of a
/// surrogate pair alone. `現金` and a zero-width space read `現金`, so a
/// name read from a file is the name the book has. The zero-width joiner
/// stays: emoji are made with it; so do combining marks.
String plainText(String text) => String.fromCharCodes([
  for (final c in text.runes)
    if (!_unseen(c)) c,
]);

bool _unseen(int c) =>
    (c < _space && c != _tab && c != _lineFeed && c != _carriageReturn) ||
    (c >= _delete && c < _firstPrintableLatin) ||
    _invisible.contains(c) ||
    (c >= _firstEmbedding && c <= _lastEmbedding) ||
    (c >= _firstIsolate && c <= _lastIsolate) ||
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

/// The direction embeddings and overrides: LRE, RLE, PDF, LRO, RLO.
const _firstEmbedding = 0x202A;
const _lastEmbedding = 0x202E;

/// The direction isolates: LRI, RLI, FSI, PDI.
const _firstIsolate = 0x2066;
const _lastIsolate = 0x2069;

/// Zero-width space and non-joiner, the direction marks, the line and
/// paragraph separators, word joiner, byte order mark, soft hyphen and
/// the Mongolian vowel separator.
const _invisible = {
  0x200B,
  0x200C,
  0x200E,
  0x200F,
  0x2028,
  0x2029,
  0x2060,
  0xFEFF,
  0x00AD,
  0x180E,
};
