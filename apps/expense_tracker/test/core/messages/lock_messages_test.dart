import 'package:expense_tracker/src/core/messages/lock_messages.dart';
import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a wait is said in hours, minutes and seconds, a started second '
      'counted whole', () {
    expect(LockWords.span(const Duration(seconds: 30)), '30 秒');
    expect(LockWords.span(const Duration(milliseconds: 29001)), '30 秒');
    expect(LockWords.span(const Duration(milliseconds: 1)), '1 秒');
    expect(LockWords.span(Duration.zero), '0 秒');
    expect(LockWords.span(const Duration(minutes: 1)), '1 分');
    expect(LockWords.span(const Duration(minutes: 4, seconds: 30)), '4 分 30 秒');
    expect(LockWords.span(const Duration(hours: 1)), '1 小時');
    expect(
      LockWords.span(const Duration(minutes: 59, seconds: 59)),
      '59 分 59 秒',
    );
    expect(
      LockWords.span(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1 小時 2 分 3 秒',
    );
  });

  test('the lock screen says how long to wait', () {
    expect(
      LockWords.waitFor(const Duration(minutes: 4, seconds: 30)),
      '輸入錯誤太多次，請等 4 分 30 秒再試',
    );
  });

  test('each auto-lock choice says what it does', () {
    expect(LockWords.autoLockDetail(AutoLock.immediately), '一離開 App 就上鎖');
    expect(LockWords.autoLockDetail(AutoLock.oneMinute), '離開 1 分鐘後上鎖');
    expect(LockWords.autoLockDetail(AutoLock.fiveMinutes), '離開 5 分鐘後上鎖');
    expect(LockWords.autoLockDetail(AutoLock.fifteenMinutes), '離開 15 分鐘後上鎖');
    expect(LockWords.autoLockDetail(AutoLock.never), '只有關閉 App 後才需要解鎖');
  });

  test('the picker says how long a trip the app started stays open', () {
    expect(
      LockWords.autoLockWhy,
      '離開 App 多久之後，回來要重新解鎖。拍收據、選檔案這類由 App 帶出去的畫面，'
      '至少 5 分鐘內不會上鎖。',
    );
  });
}
