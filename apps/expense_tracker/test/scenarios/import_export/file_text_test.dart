import 'package:domain/data_exchange.dart';
import 'package:expense_tracker/src/app/demo/preview_services.dart';
import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/features/backup/model/backup_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/places.dart';

/// The preview's backups, choosing [file] when a file is asked for.
final class _Choosing implements BackupManager {
  _Choosing(this.file);

  final FileText file;
  final _rest = DemoBackupManager();

  @override
  Future<FileText?> readFile() async => file;

  @override
  Future<bool> exportBackup() => _rest.exportBackup();
  @override
  Future<bool> exportFile(String name, String text) =>
      _rest.exportFile(name, text);
  @override
  Future<bool> exportBytes(String name, List<int> bytes) =>
      _rest.exportBytes(name, bytes);
  @override
  DateTime? get cloudCopyAt => _rest.cloudCopyAt;
  @override
  DateTime? get googleTakenAt => _rest.googleTakenAt;
  @override
  DateTime? get exportedAt => _rest.exportedAt;
  @override
  bool get hasPassword => _rest.hasPassword;
  @override
  bool get passwordBelowRule => _rest.passwordBelowRule;
  @override
  String get passwordRule => _rest.passwordRule;
  @override
  String? refusePassword(String password) => _rest.refusePassword(password);
  @override
  String get passphraseRule => _rest.passphraseRule;
  @override
  String? refusePassphrase(String passphrase) =>
      _rest.refusePassphrase(passphrase);
  @override
  Future<void> setPassword(String next) => _rest.setPassword(next);
  @override
  Future<void> changePassword(String current, String next) =>
      _rest.changePassword(current, next);
  @override
  Future<String> newRecoveryCode() => _rest.newRecoveryCode();
  @override
  bool get hasBackupPassphrase => _rest.hasBackupPassphrase;
  @override
  Future<void> setBackupPassphrase(String passphrase) =>
      _rest.setBackupPassphrase(passphrase);
  @override
  Future<void> removeBackupPassphrase() => _rest.removeBackupPassphrase();
  @override
  Future<void> resetKeys(String? currentPassword) =>
      _rest.resetKeys(currentPassword);
  @override
  bool get canUseFingerprint => _rest.canUseFingerprint;
  @override
  bool get fingerprintOn => _rest.fingerprintOn;
  @override
  Future<bool> turnFingerprint({required bool on}) =>
      _rest.turnFingerprint(on: on);
  @override
  bool get recoveryGiven => _rest.recoveryGiven;
  @override
  Future<void> lock() => _rest.lock();
  @override
  Future<String> restoreAnother() => _rest.restoreAnother();
}

/// N4: a file is read as UTF-8 or Big5 ([readFileText]); one that is
/// neither is said so, and nothing is read.
void main() {
  const csv = '日期,類型,金額,帳戶,分類\n2026-10-01,支出,120,隨身現金,飲食日常\n';

  Future<void> choose(WidgetTester tester, FileText file) async {
    await show(tester, 360, 1, book: demoLedger(), keys: _Choosing(file));
    await go(tester, ['更多', '設定', '匯入與匯出', 'CSV 檔案', '選檔案']);
  }

  testWidgets('a file read as Big5 is imported like any other', (tester) async {
    await choose(tester, const TextRead(csv, TextEncoding.big5));
    expect(find.textContaining('匯入 1 筆'), findsOneWidget);
  });

  testWidgets('a file of neither is said to be unreadable', (tester) async {
    await choose(tester, const TextUnreadable());
    expect(find.text('讀不到這個檔案，請確認是 UTF-8 或 Big5 的文字檔'), findsOneWidget);
    expect(find.textContaining('匯入 1 筆'), findsNothing);
  });
}
