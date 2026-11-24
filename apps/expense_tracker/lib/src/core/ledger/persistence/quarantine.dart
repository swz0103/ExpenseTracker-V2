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

/// The rows set aside as a book opened, by where they are kept.
final class Quarantine {
  final _rows = <String, QuarantinedRow>{};

  /// Every row set aside, in the order they were.
  List<QuarantinedRow> get rows => List.unmodifiable(_rows.values);

  bool get isEmpty => _rows.isEmpty;

  /// Whether the row [id] on [shelf] is set aside.
  bool holds(String shelf, String id) => _rows.containsKey('$shelf/$id');

  void clear() => _rows.clear();

  /// Sets the row [id] on [shelf] aside for [reason]. What reading it
  /// threw, [error], is told by its type and message alone
  /// ([quarantineDetail]); or [detail] says what did not fit.
  void record(
    String shelf,
    String id,
    QuarantineReason reason, {
    Object? error,
    String detail = '',
    int? version,
  }) {
    final row = QuarantinedRow(
      shelf,
      id,
      reason,
      detail: error == null ? detail : quarantineDetail(error),
      version: version,
    );
    _rows[row.key] = row;
  }
}

/// A change would have written over, or dropped, a row set aside; the
/// whole change is refused instead.
final class RowSetAside implements Exception {
  const RowSetAside(this.shelf);

  final String shelf;

  @override
  String toString() => 'RowSetAside($shelf)';
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

/// The rows of a notice to tell the person as the book opens (D18), and
/// the fingerprint to remember of the rows a newer version wrote. Rows
/// that cannot be read are told every opening; rows set aside because a
/// newer version wrote them are told once per distinct set: not again
/// while the set's fingerprint is the one [told] remembers. The
/// fingerprint is null when no row is newer (nothing to remember).
({List<QuarantinedRow> tell, String? fingerprint}) quarantineToTell(
  List<QuarantinedRow> rows, {
  String? told,
}) {
  final newer = [
    for (final row in rows)
      if (row.reason == QuarantineReason.newer) row,
  ];
  final fingerprint = newer.isEmpty ? null : newerFingerprint(newer);
  return (
    tell: [
      for (final row in rows)
        if (row.reason != QuarantineReason.newer || fingerprint != told) row,
    ],
    fingerprint: fingerprint,
  );
}

/// A fingerprint of a set of rows a newer version wrote: where each is
/// kept and the version that wrote it, never anything of its content.
/// The same set in any order gives the same fingerprint: its count and a
/// 32-bit FNV-1a of the sorted keys, as text, kept beside the keyring.
String newerFingerprint(List<QuarantinedRow> rows) {
  final keys = [for (final row in rows) '${row.key}@${row.version}']..sort();
  var hash = _fnvOffset;
  for (final unit in keys.join('\n').codeUnits) {
    hash ^= unit;
    // × 16777619 (2^24 + 403), modulo 2^32, kept exact on every platform.
    hash = (hash * 403 + (hash % 256) * 16777216) % 0x100000000;
  }
  return '${keys.length}:${hash.toRadixString(16).padLeft(8, '0')}';
}

/// FNV-1a's 32-bit offset basis.
const _fnvOffset = 0x811c9dc5;
