import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_backup_probe/cloud_backup_history.dart';
import 'package:cloud_backup_probe/cloud_backup_manual_flow.dart';
import 'package:cloud_backup_probe/cloud_backup_schedule.dart';
import 'package:cloud_backup_probe/cloud_backup_work.dart';
import 'package:cloud_backup_probe/google_drive_adapter.dart';
import 'package:cloud_backup_probe/google_drive_http.dart';
import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path_provider/path_provider.dart';
import 'package:persistent_jobs_probe/persistent_jobs.dart';

import 'cloud_backup_screen.dart';
import 'cloud_backup_screen_gateway.dart';
import 'engine_cloud_backup.dart';
import 'preview_engine.dart';

const googleDriveFileScope = 'https://www.googleapis.com/auth/drive.file';

/// Interactive Google authorization stays outside the ledger. The plugin owns
/// the platform token cache; the App asks for a current access token only when
/// a Drive request is about to be sent.
final class GoogleDriveSignInTokenSource implements DriveAccessTokenSource {
  GoogleDriveSignInTokenSource({String? serverClientId, GoogleSignIn? signIn})
    : serverClientId =
          serverClientId ??
          const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID'),
      _signIn = signIn ?? GoogleSignIn.instance;

  final String serverClientId;
  final GoogleSignIn _signIn;
  Future<void>? _initializing;
  GoogleSignInAccount? _account;

  bool get isConfigured => serverClientId.trim().isNotEmpty;

  Future<void> _initialize() => _initializing ??= _doInitialize();

  Future<void> _doInitialize() async {
    if (!isConfigured) {
      throw const DriveApiException(DriveApiFailure.authenticationRequired);
    }
    await _signIn.initialize(serverClientId: serverClientId.trim());
    final attempt = _signIn.attemptLightweightAuthentication();
    _account = attempt == null ? null : await attempt;
  }

  Future<void> connect() async {
    await _initialize();
    if (!_signIn.supportsAuthenticate()) {
      throw const DriveApiException(DriveApiFailure.authenticationRequired);
    }
    final account = await _signIn.authenticate(
      scopeHint: const [googleDriveFileScope],
    );
    var authorization = await account.authorizationClient
        .authorizationForScopes(const [googleDriveFileScope]);
    authorization ??= await account.authorizationClient.authorizeScopes(const [
      googleDriveFileScope,
    ]);
    if (authorization.accessToken.isEmpty) {
      throw const DriveApiException(DriveApiFailure.authenticationRequired);
    }
    _account = account;
  }

  Future<void> disconnect() async {
    await _initialize();
    await _signIn.disconnect();
    _account = null;
  }

  @override
  Future<String> accessToken() async {
    await _initialize();
    var account = _account;
    if (account == null) {
      final attempt = _signIn.attemptLightweightAuthentication();
      account = attempt == null ? null : await attempt;
      _account = account;
    }
    if (account == null) {
      throw const DriveApiException(DriveApiFailure.authenticationRequired);
    }
    final authorization = await account.authorizationClient
        .authorizationForScopes(const [googleDriveFileScope]);
    final token = authorization?.accessToken;
    if (token == null || token.isEmpty) {
      throw const DriveApiException(DriveApiFailure.authenticationRequired);
    }
    return token;
  }
}

final class AndroidCloudBackupKeyStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageNamespace: 'expense_v2_cloud_backup_runtime_v1',
      resetOnError: false,
      migrateOnAlgorithmChange: false,
    ),
  );
  static const _key = 'sqlcipher_key_v1';

  Future<StorageKey> loadOrCreate() async {
    final saved = await _storage.read(key: _key);
    if (saved != null) return StorageKey(_decode(saved));
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final encoded = base64UrlEncode(bytes);
    await _storage.write(key: _key, value: encoded);
    final verified = await _storage.read(key: _key);
    if (verified != encoded) throw StateError('Cloud backup key was not saved');
    return StorageKey(bytes);
  }

  static List<int> _decode(String value) {
    try {
      final bytes = base64Url.decode(value);
      if (bytes.length == 32) return bytes;
    } on FormatException {
      // Mapped to one non-sensitive failure below.
    }
    throw StateError('Cloud backup key is unavailable');
  }
}

Future<CloudBackupScreenGateway> createGoogleDriveCloudBackupGateway({
  required PreviewEngine engine,
  required GoogleDriveSignInTokenSource authorization,
  AndroidCloudBackupKeyStore? keys,
  Directory? root,
}) async {
  if (!authorization.isConfigured) {
    throw const DriveApiException(DriveApiFailure.authenticationRequired);
  }
  final base =
      root ??
      Directory(
        '${(await getApplicationSupportDirectory()).path}'
        '${Platform.pathSeparator}cloud-backup-v1',
      );
  if (!base.existsSync()) base.createSync(recursive: true);
  final key = await (keys ?? AndroidCloudBackupKeyStore()).loadOrCreate();
  final work = CloudBackupWorkStore.open(
    databaseFile: File('${base.path}${Platform.pathSeparator}work.db'),
    artifactDirectory: Directory(
      '${base.path}${Platform.pathSeparator}artifacts',
    ),
    key: key,
  );
  final jobs = PersistentJobStore.open(
    File('${base.path}${Platform.pathSeparator}jobs.db'),
    key,
  );
  final schedules = CloudBackupScheduleStore.open(
    File('${base.path}${Platform.pathSeparator}schedules.db'),
    key,
  );
  final provider = GoogleDriveBackupProvider(
    api: GoogleDriveRestApi(
      transport: const IoDriveHttpTransport(),
      tokens: authorization,
    ),
    reservations: work,
  );
  final runner = CloudBackupJobRunner(
    jobs: jobs,
    work: work,
    provider: provider,
  );
  final runners = {googleDriveBackupProviderId: runner};
  final providers = CloudBackupProviderRegistry([provider]);
  final flow = CloudBackupManualFlow(
    providers: providers,
    uploadTargets: [
      CloudBackupManualTarget(
        providerId: googleDriveBackupProviderId,
        schedule: (artifact, now) => runner.schedule(artifact, now: now),
      ),
    ],
  );
  final bridge = EngineCloudBackupBridge(engine: engine);
  final automatic = CloudBackupAutomaticScheduler(
    schedules: schedules,
    runners: runners,
    source: (_, backupId, dueAt) =>
        engine.exportVerifiedCloudBackup(backupId: backupId, createdAt: dueAt),
  );
  return FlowCloudBackupScreenGateway(
    flow: flow,
    providerChoices: const [
      CloudBackupProviderChoice(
        id: googleDriveBackupProviderId,
        label: 'Google Drive',
      ),
    ],
    createSource: bridge.createSource,
    restoreHandoff: bridge.restore,
    schedules: schedules,
    runners: runners,
    automaticScheduler: automatic,
    reconnectProvider: (_) => authorization.connect(),
  );
}
