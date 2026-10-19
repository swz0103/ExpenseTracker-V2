/// One CSV record per line, RFC 4180 quoting; blank lines are skipped and a
/// leading byte order mark is ignored.
List<List<String>> readCsv(String input) {
  final text = input.startsWith(_bom) ? input.substring(1) : input;
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  void endField() {
    row.add(field.toString());
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
/// quoted.
String writeCsv(List<List<String>> rows) {
  final lines = [for (final row in rows) row.map(_cell).join(',')];
  return '$_bom${lines.join('\r\n')}\r\n';
}

String _cell(String value) {
  if (!value.contains(_special)) return value;
  return '"${value.replaceAll('"', '""')}"';
}

final _special = RegExp('[",\r\n]');

const _bom = '\u{FEFF}';
