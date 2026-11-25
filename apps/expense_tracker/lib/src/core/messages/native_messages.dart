/// The words the phone's own side (the Kotlin code) shows: the app hands
/// them over with each call that needs them, so that side keeps none of
/// its own (NAT-1). Where it must speak while the app cannot run (an
/// update noticed in the background, a reminder kept by an earlier
/// version), it falls back to `NativeWords.kt`, which a test holds to
/// these (test/core/messages/native_messages_test.dart).
abstract final class NativeWords {
  /// The fingerprint or face prompt: turning the device unlock on, and
  /// unlocking with it; its button back to the password.
  static const biometricEnrol = '開啟生物辨識解鎖';
  static const biometricUnlock = '解鎖記帳本';
  static const biometricPassword = '改用密碼';

  /// How the recovery code is labelled on the clipboard.
  static const clipboardLabel = '記帳本救援碼';

  /// A reminder's button that books a recurring item due.
  static const reminderConfirm = '確認入帳';

  /// A reminder as the lock screen shows it: no amount, no name.
  static const reminderPublicTitle = '記帳本';
  static const reminderPublicText = '有一則提醒';

  /// The notification of a newer version (sideload build only): its
  /// channel in the system settings, and the notice itself, with the
  /// version when update.json names one.
  static const updateChannel = '新版本';
  static const updateChannelAbout = '有新版本可以更新時';
  static const updateTitle = '記帳本有新版本';
  static String updateTitleOf(String version) => '記帳本 $version 可以更新';
  static const updateText = '打開 App 就能更新';

  /// The reminder words, as `Reminders.kt` keeps them.
  static const reminders = <String, String>{
    'confirm': reminderConfirm,
    'publicTitle': reminderPublicTitle,
    'publicText': reminderPublicText,
  };
}
