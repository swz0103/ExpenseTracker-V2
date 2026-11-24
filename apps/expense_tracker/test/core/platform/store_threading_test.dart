import 'package:expense_tracker/src/core/diagnostics/error_log.dart';
import 'package:expense_tracker/src/core/platform/store_threading.dart';
import 'package:flutter_test/flutter_test.dart';

/// D41: a SQLite without threads is noted for 診斷, not passed over.
void main() {
  test('the SQLite the tests run on has threads: nothing noted', () {
    final before = ErrorLog.instance.count;
    expect(noteStoreThreading(), isTrue);
    expect(ErrorLog.instance.count, before);
  });

  test('one without threads is noted and the app goes on', () {
    final before = ErrorLog.instance.count;
    expect(noteStoreThreading(serialized: false), isFalse);
    expect(ErrorLog.instance.count - before, 1);
    expect(
      ErrorLog.instance.entries.first.$2,
      '啟動：資料庫執行緒模式：StateError: Bad state: SQLite is built without threads',
    );
  });
}
