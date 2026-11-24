import 'dart:io';

import 'package:storage/storage.dart';
import 'package:test/test.dart';

void main() {
  test('a write refused for want of room is told from other failures', () {
    FileSystemException failed(int code) =>
        FileSystemException('write', 'x', OSError('', code));
    // 28 is ENOSPC (Linux, Android), 112 ERROR_DISK_FULL (Windows).
    expect(isNoSpace(failed(28)), isTrue);
    expect(isNoSpace(failed(112)), isTrue);
    // 13 is EACCES: permission, not room.
    expect(isNoSpace(failed(13)), isFalse);
    expect(isNoSpace(const FileSystemException('write')), isFalse);
    expect(isNoSpace(StateError('disk full')), isFalse);
  });
}
