// Marks a test as a known defect of the audit: it states the CORRECT
// behaviour and is skipped until the work package that fixes it lands.
// Run them all anyway with `--dart-define=RUN_KNOWN_DEFECTS=true`; each
// is expected to fail until its fix is in.

const _enabled =
    bool.fromEnvironment('RUN_KNOWN_DEFECTS') ||
    String.fromEnvironment('RUN_KNOWN_DEFECTS') == '1';

/// The `skip:` argument of a known-defect test: the reason it is skipped,
/// or null when `RUN_KNOWN_DEFECTS` is set so the test runs.
String? knownDefect(String id, String package) =>
    _enabled ? null : '$id 待工作包 $package 修正';
