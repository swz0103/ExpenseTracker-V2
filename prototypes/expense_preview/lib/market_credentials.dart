import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class FugleCredentialVault {
  Future<String?> read();
  Future<void> write(String apiKey);
  Future<void> delete();
}

final class AndroidFugleCredentialVault implements FugleCredentialVault {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageNamespace: 'expense_v2_market_credentials_v1',
      resetOnError: false,
      migrateOnAlgorithmChange: false,
    ),
  );
  static const _key = 'fugle_api_key_v1';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String apiKey) => _storage.write(key: _key, value: apiKey);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

final class FugleCredentialManager {
  const FugleCredentialManager(this.vault);

  final FugleCredentialVault vault;

  Future<bool> isConfigured() async => await vault.read() != null;

  Future<void> save(String apiKey) async {
    _validate(apiKey);
    await vault.write(apiKey);
  }

  Future<void> revoke() => vault.delete();

  Future<String> requireApiKey() async {
    final value = await vault.read();
    if (value == null) throw StateError('Fugle API key is not configured');
    _validate(value);
    return value;
  }

  static void _validate(String value) {
    if (value.isEmpty ||
        value.length > 512 ||
        !RegExp(r'^[\x21-\x7E]+$').hasMatch(value)) {
      throw ArgumentError.value(value, 'apiKey', 'Invalid Fugle API key');
    }
  }
}

final class FugleCredentialPanel extends StatefulWidget {
  const FugleCredentialPanel({required this.manager, super.key});

  final FugleCredentialManager manager;

  @override
  State<FugleCredentialPanel> createState() => _FugleCredentialPanelState();
}

final class _FugleCredentialPanelState extends State<FugleCredentialPanel> {
  final _input = TextEditingController();
  bool? _configured;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final configured = await widget.manager.isConfigured();
      if (mounted) setState(() => _configured = configured);
    } catch (_) {
      if (mounted) setState(() => _message = '安全儲存空間目前無法使用。');
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.manager.save(_input.text);
      _input.clear();
      if (mounted) {
        setState(() {
          _configured = true;
          _message = 'Fugle API key 已安全儲存。';
        });
      }
    } on ArgumentError {
      if (mounted) setState(() => _message = 'API key 格式無效，請重新輸入。');
    } catch (_) {
      if (mounted) setState(() => _message = 'API key 無法儲存，請稍後重試。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.manager.revoke();
      _input.clear();
      if (mounted) {
        setState(() {
          _configured = false;
          _message = '本機 Fugle API key 已移除。';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'API key 無法移除，請稍後重試。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _input.clear();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        _configured == null
            ? '正在檢查 Fugle 設定…'
            : _configured!
            ? 'Fugle API key 已設定（內容不顯示）'
            : '尚未設定 Fugle API key',
        key: const ValueKey('fugle-key-status'),
      ),
      TextField(
        key: const ValueKey('fugle-key-input'),
        controller: _input,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(labelText: '新的 Fugle API key'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: const Text('儲存或更換 key'),
      ),
      OutlinedButton(
        onPressed: _busy || _configured != true ? null : _revoke,
        child: const Text('移除本機 key'),
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_message != null)
        Text(_message!, key: const ValueKey('fugle-key-message')),
      const Text('Key 只存於系統安全儲存空間，不寫入帳本、資料庫、匯出或雲端備份。'),
    ],
  );
}
