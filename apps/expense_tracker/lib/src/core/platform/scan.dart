/// What became of asking the phone to read a QR code, such as one of a
/// paper e-invoice's two.
sealed class ScanOutcome {
  const ScanOutcome();
}

/// A code was read: its [text].
final class ScanRead extends ScanOutcome {
  const ScanRead(this.text);

  final String text;
}

/// The person closed the scanner without a code.
final class ScanClosed extends ScanOutcome {
  const ScanClosed();
}

/// No code could be read: [failure] says which way it went wrong.
final class ScanFailed extends ScanOutcome {
  const ScanFailed(this.failure);

  final ScanFailure failure;
}

/// Why a scan did not work.
enum ScanFailure {
  /// The scanner is not on the phone and could not be fetched: Google Play
  /// services is missing, off or out of date, there is no network or
  /// room, or the download failed or took too long.
  unavailable,

  /// A scan is already open.
  busy,

  /// The scanner opened and failed.
  failed,
}

/// Opens the phone's scanner for one code. [preparing] is called when the
/// scanner must be fetched first, which can take a while, so the wait can
/// be explained.
typedef ScanQr = Future<ScanOutcome> Function({void Function()? preparing});
