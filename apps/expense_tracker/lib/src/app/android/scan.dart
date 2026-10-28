import 'channel.dart';

/// Reads a QR code with Google's code scanner (`ScanPart.kt`); null when
/// the person closes it.
Future<String?> androidScanQr() =>
    platformChannel.invokeMethod<String>('scanQr');
