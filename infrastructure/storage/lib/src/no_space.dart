import 'dart:io';

/// The system's "no space left on the device": ENOSPC on Linux and
/// Android.
const _enospc = 28;

/// The same on Windows: ERROR_DISK_FULL.
const _diskFull = 112;

/// Whether [error] is a write refused for want of room on the device: a
/// failure that goes away once space is freed, not one in the file.
bool isNoSpace(Object error) => switch (error) {
  FileSystemException(osError: OSError(errorCode: _enospc || _diskFull)) =>
    true,
  _ => false,
};
