import 'dart:io';
import 'dart:typed_data';

import 'package:core/foundation_values.dart';
import 'package:vault/backup_security.dart';

import '../../core/platform/startup.dart';
import 'platform_channel.dart';

/// This install's device unlock, when the phone can confirm a fingerprint
/// or face; null otherwise. Its id is made once and kept beside the
/// ledger, so a reinstall enrols a new key.
Future<DeviceUnlock?> androidDeviceUnlock(Directory directory) async {
  final usable = await platformChannel.invokeMethod<bool>('canUseBiometrics');
  if (usable != true) return null;
  final file = File('${directory.path}/device-id');
  if (!file.existsSync()) {
    await directory.create(recursive: true);
    await file.writeAsString('android-${PublicId.generate().value}');
  }
  return DeviceUnlock(
    (await file.readAsString()).trim(),
    const KeystoreDeviceKey(),
    hasKey: () async =>
        await platformChannel.invokeMethod<bool>('hasDeviceKey') ?? false,
  );
}

/// The Keystore's methods over the platform channel (`KeystoreHandler.kt`);
/// `context` is bound in as AES-GCM associated data.
abstract base class _KeystoreChannel implements DeviceKeyWrapper {
  const _KeystoreChannel();

  Future<List<int>> _call(
    String method,
    List<int> data,
    List<int> context,
  ) async {
    final result = await platformChannel.invokeMethod<Uint8List>(method, {
      'data': Uint8List.fromList(data),
      'context': Uint8List.fromList(context),
    });
    if (result == null) throw StateError('The device key gave nothing.');
    return result;
  }
}

/// Wraps the ledger key with an Android Keystore key bound to biometric
/// confirmation.
final class KeystoreDeviceKey extends _KeystoreChannel {
  const KeystoreDeviceKey();

  @override
  Future<List<int>> wrap(List<int> secret, List<int> context) =>
      _call('wrap', secret, context);

  @override
  Future<List<int>> unwrap(List<int> wrapped, List<int> context) =>
      _call('unwrap', wrapped, context);
}

/// Seals the key of a ledger opened without a password with an Android
/// Keystore key that never leaves the phone's secure hardware and needs no
/// fingerprint, so the ledger still opens by itself (`quickWrap` and
/// `quickUnwrap`).
final class KeystoreQuickKey extends _KeystoreChannel {
  const KeystoreQuickKey();

  @override
  Future<List<int>> wrap(List<int> secret, List<int> context) =>
      _call('quickWrap', secret, context);

  @override
  Future<List<int>> unwrap(List<int> wrapped, List<int> context) =>
      _call('quickUnwrap', wrapped, context);
}
