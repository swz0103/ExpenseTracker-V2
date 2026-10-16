import 'package:storage_sqlcipher/storage_sqlcipher.dart';

/// The app's own table in the encrypted ledger: the mark and colour chosen
/// for each category and account. The ledger itself has neither.
final looksSchema = SchemaModule('app_looks', [
  [
    '''
    CREATE TABLE app_looks (
      subject TEXT PRIMARY KEY,
      icon TEXT NOT NULL,
      color INTEGER
    ) STRICT, WITHOUT ROWID
    ''',
  ],
]);

/// A mark from the app's icon set, with a colour as 0xAARRGGBB or none
/// for the default of its kind.
typedef Look = ({String icon, int? color});

/// Reads and writes [looksSchema]. Writes go through [run] so they queue
/// behind the ledger's own commands instead of overlapping them.
final class Looks {
  Looks(this._store, this._run);

  final SqlCipherStore _store;
  final Future<void> Function(Future<void> Function() write) _run;

  /// Every saved look, by the id of its category or account.
  Map<String, Look> all() {
    final looks = <String, Look>{};
    for (final row in _store.select('SELECT * FROM app_looks')) {
      final subject = row['subject']! as String;
      final icon = row['icon']! as String;
      looks[subject] = (icon: icon, color: row['color'] as int?);
    }
    return looks;
  }

  Future<void> save(String subject, Look look) {
    return _run(() async {
      await _store.write((t) async {
        t.execute(_upsert, [subject, look.icon, look.color]);
      });
    });
  }

  static const _upsert =
      'INSERT INTO app_looks (subject, icon, color) VALUES (?, ?, ?) '
      'ON CONFLICT (subject) DO UPDATE '
      'SET icon = excluded.icon, color = excluded.color';
}
