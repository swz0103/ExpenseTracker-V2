import 'package:flutter/services.dart' show appFlavor;

/// Whether this build may update itself: the sideload build (GitHub
/// Releases) may, and so does any build made without a flavor (tests, the
/// preview); the `play` build never does, because Google Play does not
/// allow an app to update itself by other means. The one place this is
/// decided: the update code in the app and in Android (src/sideload) is
/// left out of the play build, and 關於 shows no update there.
const canSelfUpdate = appFlavor != 'play';
