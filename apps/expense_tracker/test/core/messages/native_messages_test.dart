import 'dart:io';

import 'package:expense_tracker/src/app/android/keystore_adapter.dart';
import 'package:expense_tracker/src/app/android/notification_adapter.dart';
import 'package:expense_tracker/src/core/messages/native_messages.dart';
import 'package:expense_tracker/src/features/reminders/model/calendar_sync.dart';
import 'package:expense_tracker/src/features/reminders/model/reminder_alerts.dart';
import 'package:flutter_test/flutter_test.dart';

/// The phone's own side shows no words and keeps no mark of its own
/// (NAT-1): the app hands them over with each call, and the side keeps
/// only fallbacks, in `NativeWords.kt`, for where the app cannot run.
/// This holds the fallbacks to the app's words, and each handover to the
/// fields the Kotlin side reads.
void main() {
  const folder = 'android/app/src';
  const main = '$folder/main/kotlin/io/github/swz0103/expensetracker';
  String read(String path) => File(path).readAsStringSync();

  test('the words the phone shows', () {
    expect(NativeWords.biometricEnrol, '開啟生物辨識解鎖');
    expect(NativeWords.biometricUnlock, '解鎖記帳本');
    expect(NativeWords.biometricPassword, '改用密碼');
    expect(NativeWords.clipboardLabel, '記帳本救援碼');
    expect(NativeWords.reminders, {
      'confirm': '確認入帳',
      'publicTitle': '記帳本',
      'publicText': '有一則提醒',
    });
    expect(NativeWords.updateChannel, '新版本');
    expect(NativeWords.updateChannelAbout, '有新版本可以更新時');
    expect(NativeWords.updateTitle, '記帳本有新版本');
    expect(NativeWords.updateTitleOf('0.23.0'), '記帳本 0.23.0 可以更新');
    expect(NativeWords.updateText, '打開 App 就能更新');
  });

  test('the fallbacks NativeWords.kt keeps are the app\'s words', () {
    final kotlin = {
      for (final m in RegExp(
        r'const val (\w+) = "([^"]*)"',
      ).allMatches(read('$main/NativeWords.kt')))
        m[1]!: m[2]!,
    };
    // The widget's own are held by widget_words_test.
    kotlin.removeWhere((name, _) => name.startsWith('WIDGET_'));
    expect(kotlin, {
      'REMINDER_CONFIRM': NativeWords.reminderConfirm,
      'REMINDER_PUBLIC_TITLE': NativeWords.reminderPublicTitle,
      'REMINDER_PUBLIC_TEXT': NativeWords.reminderPublicText,
      'UPDATE_CHANNEL': NativeWords.updateChannel,
      'UPDATE_CHANNEL_ABOUT': NativeWords.updateChannelAbout,
      'UPDATE_TITLE': NativeWords.updateTitle,
      'UPDATE_TITLE_OF': NativeWords.updateTitleOf('%s'),
      'UPDATE_TEXT': NativeWords.updateText,
    });
  });

  test('the fingerprint prompt is worded by the app', () {
    expect(KeystoreDeviceKey.prompt(enrol: true), {
      'title': '開啟生物辨識解鎖',
      'password': '改用密碼',
    });
    expect(KeystoreDeviceKey.prompt(enrol: false), {
      'title': '解鎖記帳本',
      'password': '改用密碼',
    });
    final handler = read('$main/KeystoreHandler.kt');
    for (final field in KeystoreDeviceKey.prompt(enrol: true).keys) {
      expect(handler, contains('call.argument<String>("$field")'));
    }
  });

  test('the reminders\' words go with the plan, and are kept for the '
      'alarms', () {
    final plan = AndroidNotifications.planFields(
      const ReminderPlan([], exact: false, wanted: {}),
    );
    expect(plan['words'], NativeWords.reminders);
    final reminders = read('$main/Reminders.kt');
    for (final name in NativeWords.reminders.keys) {
      expect(reminders, contains('word(context, "$name", '), reason: name);
    }
    expect(
      RegExp(
        r'Reminders\.keepWords\(activity, call\.argument<Map<String, Any\?>>\("words"\)\)',
      ).allMatches(read('$main/RemindersHandler.kt')),
      hasLength(3),
    );
  });

  test('the calendar mark and an event\'s length come from the app', () {
    // Events already in calendars carry the mark: it never changes.
    expect(CalendarSync.mark, '記帳本#');
    expect(CalendarSync.eventLength, const Duration(minutes: 30));
    final handler = read('$main/CalendarHandler.kt');
    expect(handler, contains('call.argument<String>("mark")'));
    expect(handler, contains('call.argument<Any>("length")'));
    final adapter = read('lib/src/app/android/calendar_adapter.dart');
    expect(
      RegExp("'mark': CalendarSync.mark").allMatches(adapter),
      hasLength(2),
    );
    expect(adapter, contains("'length': CalendarSync.eventLength"));
  });

  test('the clipboard label comes from the app', () {
    expect(
      read('$main/ClipboardHandler.kt'),
      contains('call.argument<String>("label")'),
    );
    expect(
      read('lib/src/app/android/clipboard_adapter.dart'),
      contains("'label': NativeWords.clipboardLabel"),
    );
  });
}
