/// How this build stands against the newest published one: what 關於
/// says under the version, always one of these (app_update.dart decides
/// which, update_messages.dart words it).
sealed class UpdateStatus {
  const UpdateStatus();
}

/// This build never updates itself: the `play` build, which Google Play
/// updates (distribution.dart).
final class UpdateNotOffered extends UpdateStatus {
  const UpdateNotOffered();
}

/// A build made by hand has no number to compare with the published one.
final class UpdateHandBuilt extends UpdateStatus {
  const UpdateHandBuilt();
}

/// Nobody has looked yet this run.
final class UpdateNotLooked extends UpdateStatus {
  const UpdateNotLooked();
}

/// Looking now.
final class UpdateChecking extends UpdateStatus {
  const UpdateChecking();
}

/// Looked: this build is the newest.
final class UpdateCurrent extends UpdateStatus {
  const UpdateCurrent();
}

/// Looked: [version] is newer.
final class UpdateAvailable extends UpdateStatus {
  const UpdateAvailable(this.version);

  final String version;
}

/// The newer version is being downloaded: the [share] here, 0 to 1.
final class UpdateDownloading extends UpdateStatus {
  const UpdateDownloading(this.share);

  final double share;
}

/// The last look, or the last download, did not work: [failure] is why.
final class UpdateFailed extends UpdateStatus {
  const UpdateFailed(this.failure);

  final UpdateFailure failure;
}

/// Why looking for, or fetching, a newer version did not work.
enum UpdateFailure {
  /// GitHub could not be reached: no network, or no answer in time.
  offline,

  /// GitHub answered, but not with the file asked for.
  refused,

  /// `update.json` was fetched and is not what it should be.
  unreadableFeed,

  /// Looking failed in a way nobody foresaw; the error log has it.
  checkUnforeseen,

  /// `update.json` gives a size above the most an update may weigh.
  absurdSize,

  /// The download went past the size `update.json` gave for it.
  grewPastSize,

  /// The download stopped part way.
  downloadCut,

  /// The download does not match its SHA-256 or cannot be read.
  damaged,

  /// The file is not a newer version of this app signed with its key.
  notThisApp,

  /// Downloading or installing failed in a way nobody foresaw; the error
  /// log has it.
  installUnforeseen,
}
