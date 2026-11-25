/// Review 31 finding 3: the photo the camera left while the phone closed
/// the app is taken back for the next entry; one that cannot be is
/// recorded and told (D84), not lost without a word.
library;

import 'dart:io';

import 'package:expense_tracker/src/app/android/receipt_photo_adapter.dart';
import 'package:expense_tracker/src/core/diagnostics/error_log.dart';
import 'package:expense_tracker/src/core/messages/problem_messages.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/backup_security.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('expense_tracker/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late FileBox box;
  late List<QuietStep> told;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('receipts-');
    final codec = KeyringCodec(kdf: PasswordKdf.insecureForTests);
    box = await FileBox.derive(
      (await codec.create('correct horse battery')).unlocked,
      FileBox.receipts,
    );
    told = [];
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    directory.deleteSync(recursive: true);
  });

  /// The phone, answering `takeLeftoverPhoto` with [answer].
  void phone(Future<Object?> Function() answer) =>
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'takeLeftoverPhoto');
        return answer();
      });

  test('a photo left by the camera is sealed into the receipts', () async {
    final plain = File('${directory.path}/left.jpg')
      ..writeAsBytesSync([1, 2, 3]);
    phone(() async => plain.path);
    final photos = AndroidReceipts(directory, box, failed: told.add);
    final name = await photos.takeLeftover();
    expect(name, endsWith('.etr'));
    expect(File('${directory.path}/receipts/$name').existsSync(), isTrue);
    expect(plain.existsSync(), isFalse, reason: 'the plain copy goes');
    expect(told, isEmpty);
  });

  test('none left says nothing', () async {
    phone(() async => null);
    final photos = AndroidReceipts(directory, box, failed: told.add);
    expect(await photos.takeLeftover(), isNull);
    expect(told, isEmpty);
  });

  test('one that cannot be taken back is recorded and told, not '
      'thrown', () async {
    phone(() async => throw PlatformException(code: 'io'));
    final before = ErrorLog.instance.count;
    final photos = AndroidReceipts(directory, box, failed: told.add);
    expect(await photos.takeLeftover(), isNull);
    expect(told, [QuietStep.leftoverPhoto]);
    expect(ErrorLog.instance.count, before + 1);
    expect(ErrorLog.instance.entries.first.$2, contains('收據照片'));
  });
}
