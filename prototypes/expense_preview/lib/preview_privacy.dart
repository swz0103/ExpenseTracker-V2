part of 'preview_engine.dart';

extension PreviewPrivacy on PreviewEngine {
  Future<PrivacyMode> privacyMode() => _exclusive((epoch) async {
    _require();
    String? raw;
    try {
      raw = await vault.read('privacy_v1_$_identity');
    } catch (_) {
      _check(epoch);
      return PrivacyMode.hidden;
    }
    _check(epoch);
    return raw == null || raw == 'visible'
        ? PrivacyMode.visible
        : PrivacyMode.hidden;
  });

  Future<void> setPrivacyMode(PrivacyMode mode) => _exclusive((epoch) async {
    _require();
    final slot = 'privacy_v1_$_identity';
    await vault.write(slot, mode.name);
    if (await vault.read(slot) != mode.name) throw PreviewInvalid();
    _check(epoch);
  });
}
