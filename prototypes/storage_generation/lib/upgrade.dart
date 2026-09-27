part of 'generation_store.dart';

void _digest(String value) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value))
    throw const FormatException('Invalid digest');
}

/// Immutable retry identity; sourceDigest covers the live source snapshot,
/// not its original installation fingerprint. Contains no unlock credential.
final class UpgradeRequest {
  UpgradeRequest({
    required this.operation,
    required this.sourceGeneration,
    required this.sourceDigest,
    required this.route,
    required this.fromVersion,
    required this.toVersion,
    required this.backupId,
  }) {
    _digest(sourceDigest);
    if (!RegExp(r'^[a-z][a-z0-9-]{0,79}$').hasMatch(route) ||
        fromVersion < 1 ||
        toVersion <= fromVersion ||
        toVersion > 2147483647)
      throw const FormatException('Invalid upgrade route');
  }
  final OperationId operation;
  final PublicId sourceGeneration;
  final String sourceDigest;
  final String route;
  final int fromVersion, toVersion;
  final PublicId backupId;

  String encode() => jsonEncode([
    'upgrade-v1',
    operation.toString(),
    sourceGeneration.value,
    sourceDigest,
    route,
    fromVersion,
    toVersion,
    backupId.value,
  ]);

  factory UpgradeRequest.decode(String input) {
    final value = jsonDecode(input);
    if (value case [
      'upgrade-v1',
      String operation,
      String source,
      String digest,
      String route,
      int from,
      int to,
      String backup,
    ]) {
      return UpgradeRequest(
        operation: OperationId.parse(operation),
        sourceGeneration: PublicId.parse(source),
        sourceDigest: digest,
        route: route,
        fromVersion: from,
        toVersion: to,
        backupId: PublicId.parse(backup),
      );
    }
    throw const FormatException('Invalid upgrade request');
  }
}

/// Trusted adapter result. The coordinator checks identity and publication;
/// the adapter owns route semantics and actual encrypted backup verification.
final class PreparedUpgrade {
  PreparedUpgrade(this.value, this.backupDigest) {
    _digest(backupDigest);
  }
  final String value;
  final String backupDigest;
}

final class UpgradeReceipt {
  const UpgradeReceipt(this.request, this.target, this.backupDigest);
  final UpgradeRequest request;
  final GenerationReceipt target;
  final String backupDigest;
}

const _upgradeColumns = {
  'upgrade_intents': ['operation', 'request'],
  'upgrades': ['generation', 'operation', 'backup_digest'],
};

void _createUpgradeTables(Database db) {
  db.execute('''CREATE TABLE upgrade_intents (
    operation TEXT PRIMARY KEY, request TEXT NOT NULL) STRICT''');
  db.execute('''CREATE TABLE upgrades (
    generation TEXT PRIMARY KEY REFERENCES attempts(generation),
    operation TEXT NOT NULL REFERENCES upgrade_intents(operation),
    backup_digest TEXT NOT NULL) STRICT''');
}

void _validateUpgrades(Database db) {
  final intents = <String, UpgradeRequest>{};
  for (final row in db.select('SELECT * FROM upgrade_intents')) {
    final request = UpgradeRequest.decode(row['request'] as String);
    if (request.operation.toString() != row['operation'] ||
        request.encode() != row['request'])
      throw StateError('Invalid upgrade intent');
    intents[request.operation.toString()] = request;
  }
  final seen = <String>{};
  for (final row in db.select(
    '''SELECT u.*,a.operation AS attempt_operation,a.previous
      FROM upgrades u JOIN attempts a ON a.generation=u.generation''',
  )) {
    final request = intents[row['operation']];
    if (request == null ||
        row['attempt_operation'] != row['operation'] ||
        row['previous'] != request.sourceGeneration.value)
      throw StateError('Invalid upgrade link');
    PublicId.parse(row['generation'] as String);
    _digest(row['backup_digest'] as String);
    seen.add(row['operation'] as String);
  }
  if (seen.length != intents.length ||
      db.select(
        '''SELECT a.generation
    FROM attempts a JOIN upgrade_intents i ON i.operation=a.operation
    LEFT JOIN upgrades u ON u.generation=a.generation WHERE u.generation IS NULL''',
      ).isNotEmpty)
    throw StateError('Mixed operation types');
}

UpgradeReceipt? _findUpgrade(Database db, UpgradeRequest request) {
  final op = request.operation.toString();
  final attempts = db.select('SELECT * FROM attempts WHERE operation=?', [op]);
  final intents = db.userVersion == 3
      ? db.select('SELECT request FROM upgrade_intents WHERE operation=?', [op])
      : const [];
  if ((attempts.isNotEmpty && intents.isEmpty) ||
      intents.any((row) => row['request'] != request.encode()))
    throw const GenerationUnavailable(GenerationProblem.operationConflict);
  final committed = attempts.where((row) => row['status'] == 'committed');
  if (committed.isEmpty) return null;
  final target = GenerationReceipt.fromRow(committed.single);
  final backup =
      db.select('SELECT backup_digest FROM upgrades WHERE generation=?', [
            target.generation.value,
          ]).single['backup_digest']
          as String;
  return UpgradeReceipt(request, target, backup);
}

void _reserveUpgrade(
  Database db,
  UpgradeRequest request,
  String backupDigest,
  GenerationReceipt receipt,
  void Function(String)? checkpoint,
) {
  db.execute('BEGIN IMMEDIATE');
  try {
    if (db.userVersion == 2) {
      _createUpgradeTables(db);
      db.execute('PRAGMA user_version=3');
      checkpoint?.call('upgradeCatalogWriting');
    }
    db.execute(
      'INSERT INTO upgrade_intents VALUES(?,?) ON CONFLICT(operation) DO NOTHING',
      [request.operation.toString(), request.encode()],
    );
    db.execute('INSERT INTO attempts VALUES(?,?,?,?,?,?)', [
      receipt.generation.value,
      receipt.slot.value,
      receipt.operation.toString(),
      receipt.fingerprint,
      'pending',
      request.sourceGeneration.value,
    ]);
    db.execute('INSERT INTO upgrades VALUES(?,?,?)', [
      receipt.generation.value,
      receipt.operation.toString(),
      backupDigest,
    ]);
    checkpoint?.call('upgradeRecording');
    db.execute('COMMIT');
  } catch (_) {
    if (!db.autocommit) db.execute('ROLLBACK');
    rethrow;
  }
}
