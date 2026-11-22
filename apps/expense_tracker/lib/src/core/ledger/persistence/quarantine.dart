/// Why a row of the book was set aside as it opened.
enum QuarantineReason {
  /// Not JSON, or not a record's shape at all.
  unreadable,

  /// Written by a later version of the app, whose rows this one could
  /// misread.
  newer,

  /// JSON of the right version, but a field is missing or of the wrong
  /// kind.
  invalid,
}

/// A row the book could not read as it opened. It stays on disk as it
/// is, never written over or deleted by this version, and the rest of the
/// book opens without it: one bad row does not lock the person out.
final class QuarantinedRow {
  const QuarantinedRow(
    this.shelf,
    this.id,
    this.reason, {
    this.detail = '',
    this.version,
  });

  /// Where it is kept, such as `entry`, and its key there.
  final String shelf;
  final String id;

  final QuarantineReason reason;

  /// What did not fit, in the program's words, never a value from the
  /// row: no amount, note or name.
  final String detail;

  /// The version that wrote a [QuarantineReason.newer] row.
  final int? version;

  /// The row's place, `shelf/id`, as the data source keys it.
  String get key => '$shelf/$id';

  @override
  String toString() => 'QuarantinedRow($key, ${reason.name}, $detail)';
}

/// What of [error], thrown reading a row, can be told without showing the
/// row: its type and, for a [FormatException], its message, never its
/// source text.
String quarantineDetail(Object error) {
  final said = switch (error) {
    FormatException(:final message) => message,
    _ => '',
  };
  final short = said.length > 80 ? '${said.substring(0, 80)}…' : said;
  return short.isEmpty
      ? '${error.runtimeType}'
      : '${error.runtimeType}: $short';
}
