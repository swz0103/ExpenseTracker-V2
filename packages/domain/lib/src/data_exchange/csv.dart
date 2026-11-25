/// A CSV file that cannot be read as it was written: the [line] (from 1)
/// where it goes wrong, and whether a quote opened there is never closed.
final class CsvFormatException extends FormatException {
  const CsvFormatException(super.message, this.line, {this.unclosed = false});

  final int line;
  final bool unclosed;
}

/// One record of a CSV file: its [cells], and the [line] of the file
/// (from 1, as an editor counts them) it starts on.
typedef CsvRecord = ({int line, List<String> cells});

/// The cells of each record of [input] ([readCsvRecords]).
List<List<String>> readCsv(String input) => [
  for (final record in readCsvRecords(input)) record.cells,
];

/// One CSV record per line, RFC 4180 quoting; blank lines are skipped and a
/// leading byte order mark is ignored. The `'` [writeCsv] puts before
/// words a spreadsheet would run as a formula is taken off again. Each
/// record keeps the line it starts on, counting the blank lines left out
/// and the line breaks inside quoted words, so what is said of it names
/// the line the person sees.
///
/// A quote inside a field that does not start with one is part of the
/// words (`5"` for five inches), as spreadsheets read it. Words after a
/// closing quote, such as `"ab"c`, are refused rather than guessed at, and
/// so is a quote never closed: [CsvFormatException] names the line.
List<CsvRecord> readCsvRecords(String input) {
  final text = input.startsWith(_bom) ? input.substring(1) : input;
  final rows = <CsvRecord>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  // A quoted field just closed: only a comma or a line end may follow.
  var closed = false;
  var line = 1;
  var opened = 1;
  // The line the record being read starts on.
  var starts = 1;
  void endField() {
    final cell = field.toString();
    row.add(_guarded.hasMatch(cell) ? cell.substring(1) : cell);
    field.clear();
  }

  void endRow() {
    endField();
    if (row.any((cell) => cell.isNotEmpty)) {
      rows.add((line: starts, cells: row));
    }
    row = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (quoted) {
      if (char == '\n') line++;
      if (char != '"') {
        field.write(char);
      } else if (i + 1 < text.length && text[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = false;
        closed = true;
      }
    } else if (char == ',') {
      closed = false;
      endField();
    } else if (char == '\n' || char == '\r') {
      if (char == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      closed = false;
      endRow();
      line++;
      starts = line;
    } else if (closed) {
      // Spaces after the quote are no words.
      if (char != ' ' && char != '\t') {
        throw CsvFormatException('Words after a closing quote', line);
      }
    } else if (char == '"' && field.isEmpty) {
      quoted = true;
      opened = line;
    } else {
      field.write(char);
    }
  }
  if (quoted) {
    throw CsvFormatException('A quote never closed', opened, unclosed: true);
  }
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
