/// The words of the backup settings, in one place.
abstract final class BackupWords {
  /// The Google account a Drive card's backups go to.
  static const account = '帳號';

  /// A diagnostics heading: asking Google which account is linked.
  static const accountLookup = 'Google 帳號';

  /// Backups with the receipt photos go on any network
  /// (Preferences.photosOnWifi off).
  static const photosAnyNetwork = '任何網路都一起備份';

  /// The switch that keeps backups with the photos to Wi-Fi, and what
  /// turning it off means.
  static const photosOnWifi = '只用 Wi-Fi 上傳照片';
  static const photosOnWifiOff = '關閉時行動網路也會上傳，可能用掉較多流量';
}
