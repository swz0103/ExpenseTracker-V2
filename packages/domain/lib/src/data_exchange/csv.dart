/// One CSV record per line, RFC 4180 quoting; blank lines are skipped and a
/// leading byte order mark is ignored. The `'` [writeCsv] puts before
/// words a spreadsheet would run as a formula is taken off again.
List<List<String>> readCsv(String input) {
  final text = input.startsWith(_bom) ? input.substring(1) : input;
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  void endField() {
    final cell = field.toString();
    row.add(_guarded.hasMatch(cell) ? cell.substring(1) : cell);
    field.clear();
  }

  void endRow() {
    endField();
    if (row.any((cell) => cell.isNotEmpty)) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (quoted) {
      if (char != '"') {
        field.write(char);
      } else if (i + 1 < text.length && text[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = false;
      }
    } else if (char == '"') {
      quoted = true;
    } else if (char == ',') {
      endField();
    } else if (char == '\n' || char == '\r') {
      if (char == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
    } else {
      field.write(char);
    }
  }
  if (quoted) throw const FormatException('Unclosed quote in CSV');
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

/// [rows] as CSV text that Excel opens as UTF-8 (it starts with a byte
/// order mark) with CRLF line ends. Commas, quotes and line breaks are
/// quoted. Words starting as a formula would (`=`, `+`, `-`, `@`, a tab
/// or a carriage return) get a `'` before them, so a spreadsheet opening
/// the file shows them rather than running them; numbers stay as they are.
String writeCsv(List<List<String>> rows) {
  final lines = [for (final row in rows) row.map(_cell).join(',')];
  return '$_bom${lines.join('\r\n')}\r\n';
}

String _cell(String raw) {
  final value = _risky.hasMatch(raw) && num.tryParse(raw) == null
      ? "'$raw"
      : raw;
  if (!value.contains(_special)) return value;
  return '"${value.replaceAll('"', '""')}"';
}

/// Words a spreadsheet would run, behind any `'` already there: each
/// gets one more, so taking one off on reading gives the words back.
final _risky = RegExp("^'*[=+\\-@\t\r]");
final _guarded = RegExp("^'+[=+\\-@\t\r]");

final _special = RegExp('[",\r\n]');

const _bom = '\u{FEFF}';
