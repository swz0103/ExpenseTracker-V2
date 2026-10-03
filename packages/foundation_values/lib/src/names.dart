/// Display names typed by a person: categories, tags, merchants, accounts.

/// [value] trimmed, or null when it is empty, longer than [max]
/// characters or holds control characters. Length counts characters
/// (runes), not UTF-16 units, so an emoji or a rare CJK character counts
/// once (feature audit G-22).
String? cleanName(String value, {int max = 100}) {
  final result = value.trim();
  if (result.isEmpty ||
      result.runes.length > max ||
      _control.hasMatch(result)) {
    return null;
  }
  return result;
}

/// The form two names are compared in: full-width letters, digits and
/// punctuation become half-width, the ideographic space becomes a space,
/// runs of spaces collapse and letters are lower case. So "７－ＥＬＥＶＥＮ"
/// and "7-eleven" are the same name (feature audit G-19).
String nameKey(String value) {
  final buffer = StringBuffer();
  for (final rune in value.trim().runes) {
    if (rune >= 0xff01 && rune <= 0xff5e) {
      buffer.writeCharCode(rune - 0xfee0);
    } else if (rune == 0x3000) {
      buffer.write(' ');
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString().replaceAll(_spaces, ' ').toLowerCase();
}

final _control = RegExp(r'[\x00-\x1f\x7f]');
final _spaces = RegExp(r' {2,}');
