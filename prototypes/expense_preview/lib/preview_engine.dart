import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:entry_drafts/entry_drafts.dart';
import 'package:data_exchange/data_exchange.dart';

import 'local_draft_store.dart';
import 'privacy_presentation.dart' show PrivacyMode;
export 'privacy_presentation.dart' show PrivacyMode;
export 'local_draft_store.dart' show DraftUnavailable, DraftNeedsResolution;

export 'package:entry_drafts/entry_drafts.dart';

import 'package:accounts/accounts.dart';
import 'package:backup_envelope_probe/envelope.dart';
import 'package:categories/categories.dart';
import 'package:tags/tags.dart';
import 'package:merchants/merchants.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:reports/reports.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:ledger_generation_probe/safety_backup.dart';
import 'package:storage_generation_probe/generation_store.dart';

part 'preview_categories.dart';
part 'preview_tags.dart';
part 'preview_merchants.dart';
part 'preview_copy.dart';
part 'preview_drafts.dart';
part 'preview_privacy.dart';
part 'preview_upgrade.dart';
part 'preview_simple_import.dart';
part 'preview_simple_export.dart';

abstract interface class PreviewVault {
  Future<String?> read(String name);
  Future<void> write(String name, String value);
}

final class PreviewLocked implements Exception {}

final class PreviewBusy implements Exception {}

final class PreviewInvalid implements Exception {}

/// Profile credentials are valid, but required local data cannot be validated.
/// Keep its files intact and expose only read-only recovery paths.
final class PreviewDataUnavailable implements Exception {}

final class PreviewSplitInvalid implements Exception {}

final class PreviewTransferAccountInvalid implements Exception {}

final class PreviewUpgradeRequired implements Exception {}

/// Version opened by the V2 application; older local V2 ledgers require the
/// explicit, safety-backed upgrade flow before a session becomes available.
const currentPreviewSchemaVersion = 14;

/// User-facing abilities of one V2 data generation. Keep schema numbers at
/// the application boundary so widgets do not encode migration history.
final class PreviewCapabilities {
  PreviewCapabilities(this.schemaVersion) {
    if (schemaVersion < 3 || schemaVersion > 14) {
      throw ArgumentError.value(schemaVersion, 'schemaVersion');
    }
  }

  final int schemaVersion;
  bool get categories => schemaVersion >= 4;
  bool get categoryReferences => schemaVersion >= 5;
  bool get split => categoryReferences;
  bool get tags => schemaVersion >= 6;
  bool get merchants => schemaVersion >= 7;
  bool get transfers => schemaVersion >= 8;
  bool get crossCurrencyTransfers => schemaVersion >= 9;
  bool get refunds => schemaVersion >= 10;
  bool get reversals => schemaVersion >= 11;
  bool get notes => schemaVersion >= 12;
  bool get corrections => schemaVersion >= 13;
  bool get tombstones => schemaVersion >= 14;
}

typedef StoreFactory = LedgerStore Function(Directory, PublicId, int);

/// Application coordinator. Password is retained only while foreground/unlocked.
/// Platform vault owns local keys; portable backup is the recovery boundary.
final class PreviewEngine {
  PreviewEngine(
    this.directory,
    this.vault,
    this.factory, {
    this.schemaVersion = currentPreviewSchemaVersion,
    this.upgradeCheckpoint,
    this.draftCheckpoint,
  }) : capabilities = PreviewCapabilities(schemaVersion);
  final Directory directory;
  final PreviewVault vault;
  final StoreFactory factory;
  final int schemaVersion;
  final PreviewCapabilities capabilities;
  final void Function(String)? upgradeCheckpoint;
  final void Function(String)? draftCheckpoint;
  LocalDraftStore? _draftStore;
  PublicId? _identity;
  File get _profile => File('${directory.path}/profile.envelope');
  File get _pendingProfile => File('${directory.path}/profile.pending');
  bool _busy = false;
  Completer<void>? _operationDone;
  bool _draftActive = false;
  bool _importActive = false;
  int _epoch = 0;
  String? _password;
  String? _recovery;
  WorkspaceId? _workspace;
  WorkspaceId? _initialWorkspace;
  LedgerStore? _store;
  LedgerSession? _session;
  Completer<void>? _release;
  Future<void>? _lease;
  Future<void>? _closing;
  bool get isUnlocked => _password != null && _session != null;
  WorkspaceId get workspace {
    _require();
    return _workspace!;
  }

  Future<bool> hasProfile() async {
    final published = await _profile.exists();
    final staged = await _pendingProfile.exists();
    if (published && staged) throw PreviewInvalid();
    if (published || staged) return true;
    // A missing profile never authorizes replacing retained financial data.
    if (await directory.exists() && !(await directory.list().isEmpty)) {
      throw PreviewInvalid();
    }
    return false;
  }

  Future<T> _exclusive<T>(Future<T> Function(int) work) async {
    if (_busy) throw PreviewBusy();
    _busy = true;
    final done = Completer<void>();
    _operationDone = done;
    try {
      return await work(_epoch);
    } finally {
      _busy = false;
      _operationDone = null;
      done.complete();
    }
  }

  void _check(int epoch) {
    if (epoch != _epoch) throw PreviewLocked();
  }

  void _require() {
    if (!isUnlocked) throw PreviewLocked();
  }

  Future<CreatedBackup> prepareSetup(String password) =>
      _exclusive((epoch) async {
        if (await hasProfile()) throw PreviewInvalid();
        final draft = await EnvelopeCodec().create(
          utf8.encode(
            jsonEncode({
              'version': 1,
              'identity': PublicId.generate().value,
              'workspace': PublicId.generate().value,
              'initialization': PublicId.generate().value,
            }),
          ),
          password: password,
        );
        _check(epoch);
        return draft;
      });

  Future<void> finishSetup(
    CreatedBackup draft,
    String password, {
    required bool savedRecovery,
  }) => _exclusive((epoch) async {
    if (!savedRecovery || await hasProfile()) throw PreviewInvalid();
    final bytes = await EnvelopeCodec().openWithPassword(
      draft.envelope,
      password,
    );
    final info = _profileInfo(bytes);
    if (utf8.decode(
          await EnvelopeCodec().openWithRecovery(
            draft.envelope,
            draft.recoveryKey,
          ),
        ) !=
        utf8.decode(bytes)) {
      throw PreviewInvalid();
    }
    _check(epoch);
    await directory.create(recursive: true);
    final name = 'recovery_${info.identity.value}';
    if (await vault.read(name) != null) throw PreviewInvalid();
    await vault.write(name, draft.recoveryKey);
    if (await vault.read(name) != draft.recoveryKey) throw PreviewInvalid();
    _check(epoch);
    final stage = File('${directory.path}/profile.pending');
    await stage.create(exclusive: true);
    await stage.writeAsString(draft.envelope, flush: true);
    if (await stage.readAsString() != draft.envelope) throw PreviewInvalid();
    // Keep the profile pending until a validated empty ledger is published.
    // A published profile then always implies an existing committed ledger.
    await _unlock(password, epoch);
  });

  Future<void> unlock(String password) =>
      _exclusive((epoch) => _unlock(password, epoch));
  Future<void> upgrade(String password) =>
      _exclusive((epoch) => _unlock(password, epoch, allowUpgrade: true));
  Future<void> _unlock(
    String password,
    int epoch, {
    bool allowUpgrade = false,
  }) async {
    await _closeLease();
    _password = null;
    _recovery = null;
    await hasProfile();
    final source = await _profile.exists() ? _profile : _pendingProfile;
    if (await source.length() > 16384) throw PreviewInvalid();
    final envelope = await source.readAsString();
    final bytes = await EnvelopeCodec().openWithPassword(envelope, password);
    final info = _profileInfo(bytes);
    // The password has authenticated the profile. Missing, unreadable or
    // mismatched secure recovery state is now a local data-health failure;
    // never offer setup or replace the published profile to recover from it.
    late final String? recovery;
    try {
      recovery = await vault.read('recovery_${info.identity.value}');
    } catch (_) {
      throw PreviewDataUnavailable();
    }
    _check(epoch);
    if (recovery == null) throw PreviewDataUnavailable();
    late final String recovered;
    try {
      recovered = utf8.decode(
        await EnvelopeCodec().openWithRecovery(envelope, recovery),
      );
    } catch (_) {
      throw PreviewDataUnavailable();
    }
    if (recovered != utf8.decode(bytes)) throw PreviewDataUnavailable();
    _check(epoch);
    final pending = source.path == _pendingProfile.path;
    final ledgerDirectory = Directory('${directory.path}/ledger');
    if (!pending &&
        !await File('${ledgerDirectory.path}/catalog.db').exists()) {
      throw PreviewDataUnavailable();
    }
    final store = factory(ledgerDirectory, info.identity, schemaVersion);
    // The profile password was authenticated above. A failure from the
    // published generation is a data-health failure, not a bad password.
    // Never initialize or replace a published Ledger while diagnosing it.
    late InstalledFixture? current;
    try {
      current = await store.generations.current();
    } catch (_) {
      throw PreviewDataUnavailable();
    }
    if (current == null) {
      if (!pending) throw PreviewDataUnavailable();
      await store.initialize(info.initialization);
      current = await store.generations.current();
    }
    _check(epoch);
    if (current == null) throw PreviewDataUnavailable();
    final sourceVersion = (jsonDecode(current.value) as Map)['schema'];
    if (sourceVersion != schemaVersion) {
      if (sourceVersion is! int || sourceVersion > schemaVersion) {
        throw PreviewInvalid();
      }
      if (!allowUpgrade) throw PreviewUpgradeRequired();
      // Upgrading a ledger cannot silently strand local staging under an old
      // generation binding. Resolve it in the source version first.
      if (await File('${directory.path}/manual-draft.enc').exists() ||
          await File('${directory.path}/manual-draft.pending').exists()) {
        final sourceStore = factory(
          ledgerDirectory,
          info.identity,
          sourceVersion,
        );
        await sourceStore.withSession((session) async {
          final spaces = await session.workspaces();
          final drafts = LocalDraftStore(
            directory,
            info.identity,
            current!.receipt.generation,
            spaces.isEmpty ? info.workspace : spaces.single,
            vault.read,
            vault.write,
          );
          if (await drafts.read() != null) throw DraftNeedsResolution();
          // Remove an empty completion marker before changing its binding.
          if (await drafts.file.exists()) await drafts.discard();
        });
      }
      _check(epoch);
      await _upgradeLedger(
        info.identity,
        sourceVersion,
        password,
        recovery,
        epoch,
      );
      current = await store.generations.current();
    }
    _check(epoch);
    if (pending) await source.rename(_profile.path);
    _store = store;
    await _openLease();
    try {
      final spaces = await _session!.workspaces();
      if (spaces.length > 1) throw PreviewInvalid();
      _check(epoch);
      _workspace = spaces.isEmpty ? info.workspace : spaces.single;
      _initialWorkspace = info.workspace;
      _identity = info.identity;
      _password = password;
      _recovery = recovery;
      _draftStore = LocalDraftStore(
        directory,
        info.identity,
        current!.receipt.generation,
        _workspace!,
        vault.read,
        vault.write,
        checkpoint: draftCheckpoint,
      );
    } catch (_) {
      await _closeLease();
      rethrow;
    }
  }

  Future<void> _openLease() async {
    await _closing;
    final ready = Completer<void>();
    final release = Completer<void>();
    _release = release;
    _lease = _store!
        .withSession((session) async {
          _session = session;
          ready.complete();
          await release.future;
        })
        .catchError((Object error, StackTrace trace) {
          if (!ready.isCompleted) {
            ready.completeError(error, trace);
          } else {
            Error.throwWithStackTrace(error, trace);
          }
        });
    await ready.future;
  }

  Future<void> _closeLease({Future<void>? waitFor}) {
    _session = null;
    final release = _release;
    final lease = _lease;
    _release = null;
    _lease = null;
    if (lease == null) return _closing ?? Future.value();
    final previous = _closing;
    final drafts = _draftStore;
    _draftStore = null;
    _closing = () async {
      await previous;
      await waitFor;
      await drafts?.drained;
      if (release != null && !release.isCompleted) release.complete();
      await lease;
    }();
    return _closing!;
  }

  Future<void> lock() {
    _epoch++;
    _password = null;
    _recovery = null;
    _workspace = null;
    _initialWorkspace = null;
    _identity = null;
    return _closeLease(
      waitFor: _draftActive || _importActive ? _operationDone?.future : null,
    );
  }

  Future<List<LedgerActivity>> activity(
    PublicId selected, {
    LedgerActivityCursor? before,
  }) => _exclusive((epoch) async {
    _require();
    final result = await _session!.activity(
      _workspace!,
      selected,
      before: before,
    );
    _check(epoch);
    return result;
  });

  Future<List<AccountSummary>> accounts() => _exclusive((epoch) async {
    _require();
    final result = await _session!.accounts(_workspace!);
    _check(epoch);
    return result;
  });
  Future<List<LedgerEntry>> entries({LedgerEntry? before}) =>
      _exclusive((epoch) async {
        _require();
        final result = await _session!.entries(_workspace!, before: before);
        _check(epoch);
        return result;
      });
  Future<List<LedgerEntry>> searchEntries(
    LedgerSearchQuery query, {
    LedgerEntry? before,
  }) => _exclusive((epoch) async {
    _require();
    final result = await _session!.searchEntries(
      _workspace!,
      query,
      before: before,
    );
    _check(epoch);
    return result;
  });
  Future<MonthlyReport> monthlyReport(ReportMonth month) =>
      _exclusive((epoch) async {
        _require();
        final result = await _session!.monthlyReport(_workspace!, month);
        _check(epoch);
        return result;
      });
  Future<List<LedgerEntry>> deletedEntries({LedgerEntry? before}) =>
      _exclusive((epoch) async {
        _require();
        final result = await _session!.deletedEntries(
          _workspace!,
          before: before,
        );
        _check(epoch);
        return result;
      });
  Future<void> createAccount(Account account, Posting opening) =>
      _exclusive((epoch) async {
        _require();
        if (account.workspace != _workspace) throw PreviewInvalid();
        await _session!.createAccount(account, opening);
        _check(epoch);
      });
  Future<void> post(
    Posting posting, {
    Iterable<TagSelection> tags = const [],
    MerchantSelection? merchant,
  }) {
    final selections = List<TagSelection>.unmodifiable(tags);
    return _exclusive((epoch) async {
      _require();
      if (posting.operation.workspace != _workspace) throw PreviewInvalid();
      await _session!.post(posting, tags: selections, merchant: merchant);
      _check(epoch);
    });
  }

  Future<void> tombstone(PostingTombstone command) => _exclusive((epoch) async {
    _require();
    if (!capabilities.tombstones || command.operation.workspace != _workspace) {
      throw PreviewInvalid();
    }
    await _session!.tombstone(command);
    _check(epoch);
  });

  Future<String> exportBackup() => _exclusive((epoch) async {
    _require();
    await _requireNoDraft();
    _check(epoch);
    final password = _password!;
    final recovery = _recovery!;
    final snapshot = await _session!.snapshot();
    validatePreviewSnapshot(snapshot, schemaVersion: schemaVersion);
    final backup = await EnvelopeCodec().create(
      snapshot,
      password: password,
      recoveryKey: recovery,
    );
    if (utf8.decode(
              await EnvelopeCodec().openWithPassword(backup.envelope, password),
            ) !=
            utf8.decode(snapshot) ||
        utf8.decode(
              await EnvelopeCodec().openWithRecovery(backup.envelope, recovery),
            ) !=
            utf8.decode(snapshot)) {
      throw PreviewInvalid();
    }
    _check(epoch);
    return backup.envelope;
  });

  Future<List<File>> _safetyCopies() async {
    final files = <File>[];
    if (!await directory.exists()) return files;
    await for (final item in directory.list(followLinks: false)) {
      final name = item.uri.pathSegments.last;
      if (item is File &&
          RegExp(r'^before-restore-[0-9a-f-]{36}\.envelope$').hasMatch(name)) {
        files.add(item);
      }
    }
    final dated = await Future.wait(
      files.map(
        (file) async => (file: file, modified: (await file.stat()).modified),
      ),
    );
    dated.sort((a, b) {
      final byDate = b.modified.compareTo(a.modified);
      return byDate != 0 ? byDate : b.file.path.compareTo(a.file.path);
    });
    return dated.map((entry) => entry.file).toList();
  }

  Future<List<File>> _upgradeCopies() async {
    final folder = Directory('${directory.path}/upgrade-backups');
    if (!await folder.exists()) return [];
    final files = <File>[];
    await for (final item in folder.list(followLinks: false)) {
      if (item is File &&
          RegExp(r'^[0-9a-f-]{36}\.envelope$')
              .hasMatch(item.uri.pathSegments.last)) {
        files.add(item);
      }
    }
    final dated = await Future.wait(
      files.map(
        (file) async => (file: file, modified: (await file.stat()).modified),
      ),
    );
    dated.sort((a, b) {
      final byDate = b.modified.compareTo(a.modified);
      return byDate != 0 ? byDate : b.file.path.compareTo(a.file.path);
    });
    return dated.map((entry) => entry.file).toList();
  }

  Future<bool> hasLockedUpgradeCopy() => _exclusive((epoch) async {
    final found = (await _upgradeCopies()).isNotEmpty;
    _check(epoch);
    return found;
  });

  /// Upgrade attempts can leave an incomplete newest file. Search newest first
  /// for a complete, authenticated older-schema snapshot without opening the
  /// current ledger or replacing its generation.
  Future<String> exportLockedUpgradeCopy(
    String credential, {
    required bool recovery,
  }) => _exclusive((epoch) async {
    if (isUnlocked || credential.isEmpty) throw PreviewInvalid();
    for (final file in await _upgradeCopies()) {
      _check(epoch);
      try {
        if (await file.length() > EnvelopeCodec.maxEnvelopeCharacters) {
          continue;
        }
        final saved = await file.readAsString();
        final bytes = recovery
            ? await EnvelopeCodec().openWithRecovery(saved, credential)
            : await EnvelopeCodec().openWithPassword(saved, credential);
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map<String, dynamic>) continue;
        final version = decoded['schema'];
        if (version is! int || version < 3 || version >= schemaVersion) {
          continue;
        }
        validatePreviewSnapshot(bytes, schemaVersion: version);
        _check(epoch);
        return saved;
      } catch (_) {
        // A partial or damaged attempt must not hide an older verified copy.
      }
    }
    _check(epoch);
    throw PreviewInvalid();
  });

  Future<bool> hasSafetyCopy() => _exclusive((epoch) async {
    _require();
    final found = (await _safetyCopies()).isNotEmpty;
    _check(epoch);
    return found;
  });

  /// Read-only escape hatch when a damaged local ledger cannot be unlocked.
  /// The user must prove possession of a credential for the saved envelope;
  /// this never opens or replaces the current ledger.
  Future<bool> hasLockedSafetyCopy() => _exclusive((epoch) async {
    final found = (await _safetyCopies()).isNotEmpty;
    _check(epoch);
    return found;
  });

  Future<String> exportLockedSafetyCopy(
    String credential, {
    required bool recovery,
  }) => _exclusive((epoch) async {
    if (isUnlocked || credential.isEmpty) throw PreviewInvalid();
    Object? failure;
    for (final file in await _safetyCopies()) {
      _check(epoch);
      try {
        if (await file.length() > EnvelopeCodec.maxEnvelopeCharacters) {
          failure ??= PreviewInvalid();
          continue;
        }
        final saved = await file.readAsString();
        final bytes = recovery
            ? await EnvelopeCodec().openWithRecovery(saved, credential)
            : await EnvelopeCodec().openWithPassword(saved, credential);
        validatePreviewSnapshot(bytes, schemaVersion: schemaVersion);
        _check(epoch);
        return saved;
      } catch (error) {
        // An interrupted newer restore must not hide an older verified copy.
        failure ??= error;
      }
    }
    _check(epoch);
    throw failure ?? PreviewInvalid();
  });

  Future<String> exportPreviousBackup() => _exclusive((epoch) async {
    _require();
    final password = _password!;
    final recovery = _recovery!;
    Object? failure;
    for (final file in await _safetyCopies()) {
      _check(epoch);
      try {
        if (await file.length() > EnvelopeCodec.maxEnvelopeCharacters) {
          failure ??= PreviewInvalid();
          continue;
        }
        final saved = await file.readAsString();
        final codec = EnvelopeCodec();
        final bytes = await codec.openWithPassword(saved, password);
        if (utf8.decode(await codec.openWithRecovery(saved, recovery)) !=
            utf8.decode(bytes)) {
          throw PreviewInvalid();
        }
        validatePreviewSnapshot(bytes, schemaVersion: schemaVersion);
        _check(epoch);
        return saved;
      } catch (error) {
        failure ??= error;
      }
    }
    _check(epoch);
    throw failure ?? PreviewInvalid();
  });

  /// User confirms replacement. Preserve a verified encrypted safety copy first.
  /// Imported credentials unlock that file only; future exports use this app profile.
  Future<void> importBackup(
    String envelope,
    String credential, {
    required bool recovery,
  }) => _exclusive((epoch) async {
    _require();
    await _requireNoDraft();
    _check(epoch);
    final codec = EnvelopeCodec();
    final bytes = recovery
        ? await codec.openWithRecovery(envelope, credential)
        : await codec.openWithPassword(envelope, credential);
    final canonical = validatePreviewSnapshot(
      bytes,
      schemaVersion: schemaVersion,
    );
    _check(epoch);
    final password = _password!;
    final key = _recovery!;
    final prior = await _session!.snapshot();
    final safety = await codec.create(
      prior,
      password: password,
      recoveryKey: key,
    );
    final file = File(
      '${directory.path}/before-restore-${PublicId.generate().value}.envelope',
    );
    await file.create(exclusive: true);
    await file.writeAsString(safety.envelope, flush: true);
    final saved = await file.readAsString();
    if (saved != safety.envelope ||
        utf8.decode(await codec.openWithPassword(saved, password)) !=
            utf8.decode(prior) ||
        utf8.decode(await codec.openWithRecovery(saved, key)) !=
            utf8.decode(prior)) {
      throw PreviewInvalid();
    }
    _check(epoch);
    final priorDraftStore = _draftStore!;
    await priorDraftStore.discard();
    draftCheckpoint?.call('draft-restore-cleared');
    _check(epoch);
    await _closeLease();
    try {
      // Publication is a bounded atomic operation; backgrounding after acceptance
      // can finish it, but does not reopen an unlocked UI.
      await _store!.generations.install(
        utf8.decode(canonical),
        OperationId(PublicId.generate()),
      );
    } finally {
      if (_epoch == epoch) {
        final current = await _store!.generations.current();
        draftCheckpoint?.call('draft-restore-ready');
        _check(epoch);
        await _openLease();
        try {
          draftCheckpoint?.call('draft-restore-opened');
          _check(epoch);
          final spaces = await _session!.workspaces();
          _check(epoch);
          _workspace = spaces.isEmpty ? _initialWorkspace! : spaces.single;
          _draftStore = LocalDraftStore(
            directory,
            priorDraftStore.identity,
            current!.receipt.generation,
            _workspace!,
            vault.read,
            vault.write,
            checkpoint: draftCheckpoint,
          );
        } catch (_) {
          await _closeLease();
          rethrow;
        }
      }
    }
    _check(epoch);
  });
}

({PublicId identity, WorkspaceId workspace, OperationId initialization})
_profileInfo(List<int> bytes) {
  final value = jsonDecode(utf8.decode(bytes));
  if (value is! Map || value.length != 4 || value['version'] != 1) {
    throw PreviewInvalid();
  }
  return (
    identity: PublicId.parse(value['identity'] as String),
    workspace: WorkspaceId.parse(value['workspace'] as String),
    initialization: OperationId.parse(value['initialization'] as String),
  );
}

/// Restrict this UI to the subset it can represent; full import validation still
/// runs on the encrypted stage before publication.
List<int> validatePreviewSnapshot(List<int> bytes, {int schemaVersion = 5}) {
  final capabilities = PreviewCapabilities(schemaVersion);
  late List<int> canonical;
  try {
    canonical = validateSessionCapacity(
      bytes,
      categoryAware: capabilities.categories,
      categoryReferences: capabilities.categoryReferences,
      tagsAware: capabilities.tags,
      merchantsAware: capabilities.merchants,
      transfersAware: capabilities.transfers,
      fxTransfersAware: capabilities.crossCurrencyTransfers,
      refundsAware: capabilities.refunds,
      reversalsAware: capabilities.reversals,
      notesAware: capabilities.notes,
      correctionsAware: capabilities.corrections,
      tombstonesAware: capabilities.tombstones,
    );
  } on PreviewCapacity {
    throw PreviewInvalid();
  }
  final tables = (jsonDecode(utf8.decode(canonical)) as Map)['tables'] as Map;
  final rows = <dynamic>[
    ...tables['accounts'] as List,
    if (tables.containsKey('categories')) ...tables['categories'] as List,
    if (tables.containsKey('tags')) ...tables['tags'] as List,
    if (tables.containsKey('merchants')) ...tables['merchants'] as List,
  ];
  if (rows.map((a) => a['workspace']).toSet().length > 1) {
    throw PreviewInvalid();
  }
  return canonical;
}
