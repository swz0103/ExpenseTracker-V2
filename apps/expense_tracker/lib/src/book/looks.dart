import 'dart:convert';

import 'package:core/foundation_values.dart';
import 'package:storage/ledger_sqlcipher.dart';
import 'package:storage/storage_sqlcipher.dart';

/// A mark from the app's icon set, with a colour as 0xAARRGGBB or none
/// for the default of its kind.
typedef Look = ({String icon, int? color});

/// The mark and colour chosen for each category and account. The ledger
/// itself has neither, so they are kept as app events in its journal:
/// backups carry them and a restore brings them back. Writes go through
/// [run] so they queue behind the ledger's own commands.
final class Looks {
  Looks(this._store, this._workspace, this._run);

  static const kind = '${appEventPrefix}look';

  final SqlCipherStore _store;
  final WorkspaceId _workspace;
  final Future<void> Function(Future<void> Function() write) _run;

  /// Every saved look, by the id of its category or account; the latest
  /// wins.
  Map<String, Look> all() {
    final rows = _store.select(
      'SELECT payload FROM events WHERE workspace = ? AND kind = ? '
      'ORDER BY seq',
      [_workspace.toString(), kind],
    );
    final looks = <String, Look>{};
    for (final row in rows) {
      final json =
          jsonDecode(row['payload']! as String) as Map<String, Object?>;
      final subject = json['subject']! as String;
      looks[subject] = (
        icon: json['icon']! as String,
        color: json['color'] as int?,
      );
    }
    return looks;
  }

  Future<void> save(String subject, Look look) {
    final payload = jsonEncode({
      'subject': subject,
      'icon': look.icon,
      'color': look.color,
    });
    return _run(() async {
      await _store.write((t) async {
        t.append(
          id: PublicId.generate(),
          workspace: _workspace,
          kind: kind,
          payload: payload,
        );
      });
    });
  }
}
