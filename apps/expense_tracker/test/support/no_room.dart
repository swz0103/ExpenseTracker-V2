import 'dart:convert';
import 'dart:io';

/// Files as they are, but the new keys cannot be written: no space left
/// on the device (ENOSPC, 28).
final class NoRoom extends IOOverrides {
  @override
  File createFile(String path) {
    final file = super.createFile(path);
    return path.endsWith('/keyring.json.new') ? _Full(file) : file;
  }
}

final class _Full implements File {
  _Full(this._file);

  final File _file;

  @override
  String get path => _file.path;

  @override
  Future<bool> exists() => _file.exists();

  @override
  bool existsSync() => _file.existsSync();

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      _file.delete(recursive: recursive);

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) => Future.error(
    FileSystemException(
      'write',
      path,
      const OSError('No space left on device', 28),
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not needed here');
}
