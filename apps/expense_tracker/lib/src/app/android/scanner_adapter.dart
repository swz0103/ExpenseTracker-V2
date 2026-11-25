import 'package:flutter/services.dart';

import '../../core/diagnostics/error_log.dart';
import '../../core/messages/scan_messages.dart';
import '../../core/platform/scan.dart';
import 'platform_channel.dart';
import '../../core/diagnostics/app_fault.dart';

/// Reads a QR code with Google's code scanner (`ScanHandler.kt`). The
/// scanner is a part Google Play services fetches the first time: the
/// phone is asked whether it is there, and [preparing] is called when it
/// is not, before the wait for it starts. Whatever keeps a code from being
/// read is kept in the error log with the phone's reason, and answered as
/// a [ScanFailed] for the form to word; nothing is thrown.
Future<ScanOutcome> androidScanQr({void Function()? preparing}) async {
  try {
    final ready = await platformChannel.invokeMethod<bool>('scanReady');
    if (!(ready ?? false)) preparing?.call();
    final text = await platformChannel.invokeMethod<String>('scanQr');
    return text == null ? const ScanClosed() : ScanRead(text);
  } on PlatformException catch (error) {
    final failure = switch (error.code) {
      'install' => ScanFailure.unavailable,
      'busy' => ScanFailure.busy,
      _ => ScanFailure.failed,
    };
    // A second tap while the scanner is open is no fault.
    if (failure != ScanFailure.busy) {
      ErrorLog.instance.record(
        ScanMessages.step,
        ScanFault(error.code, error.details),
      );
    }
    return ScanFailed(failure);
  } on MissingPluginException catch (error) {
    ErrorLog.instance.record(ScanMessages.step, error);
    return const ScanFailed(ScanFailure.failed);
  }
}

/// What the phone said of a scan that failed, for the error log: its code
/// (`install`, `scan`) and its reason, a name such as `NETWORK_ERROR` or
/// `INSTALL_TIMEOUT` (`ScanFault.kt`). Only a name made of capital letters
/// and underscores is kept of the reason; anything else is left out.
final class ScanFault implements AppFault {
  ScanFault(this.code, Object? reason)
    : reason = reason is String && _name.hasMatch(reason) ? reason : null;

  static final _name = RegExp(r'^[A-Z_]+$');

  final String code;
  final String? reason;

  @override
  String toString() => [code, ?reason].join(' ');
}
