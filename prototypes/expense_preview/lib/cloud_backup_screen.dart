import 'package:cloud_backup_probe/cloud_backup.dart';
import 'package:cloud_backup_probe/cloud_backup_history.dart';
import 'package:cloud_backup_probe/cloud_backup_manual_flow.dart';
import 'package:cloud_backup_probe/cloud_backup_schedule.dart';
import 'package:cloud_backup_probe/cloud_backup_work.dart';
import 'package:flutter/material.dart';

final class CloudBackupProviderChoice {
  const CloudBackupProviderChoice({required this.id, required this.label});

  final String id;
  final String label;
}

final class CloudBackupRuntimeReport {
  const CloudBackupRuntimeReport({required this.pendingJobs, this.lastFailure});

  final int pendingJobs;
  final CloudBackupWorkFailure? lastFailure;
}

abstract interface class CloudBackupRuntimeGateway {
  Future<CloudBackupRuntimeReport> maintainRuntime(
    String providerId,
    DateTime now,
  );
}

abstract interface class CloudBackupScreenGateway {
  List<CloudBackupProviderChoice> get providers;

  bool canReconnect(String providerId);

  Future<void> reconnect(String providerId);

  Future<void> createBackup(String providerId);

  Future<List<RemoteBackupMetadata>> history(String providerId);

  Future<void> restore({
    required String providerId,
    required RemoteBackupMetadata backup,
    required CloudBackupCredentialKind credentialKind,
    required String credential,
  });

  Future<CloudBackupRetentionPlan> previewRetention({
    required String providerId,
    required int keepLatest,
    required DateTime now,
  });

  Future<void> applyRetention(CloudBackupRetentionPlan plan);

  Future<CloudBackupScheduleRecord?> schedule(String providerId);

  Future<void> configureSchedule({
    required String providerId,
    required bool enabled,
    required Duration interval,
    required DateTime firstDueAt,
    required DateTime now,
  });
}

final class CloudBackupScreen extends StatefulWidget {
  const CloudBackupScreen({
    required this.gateway,
    this.now = DateTime.now,
    this.embedded = false,
    this.onRestored,
    super.key,
  });

  final CloudBackupScreenGateway gateway;
  final DateTime Function() now;
  final bool embedded;
  final Future<void> Function()? onRestored;

  @override
  State<CloudBackupScreen> createState() => _CloudBackupScreenState();
}

final class _CloudBackupScreenState extends State<CloudBackupScreen> {
  String? _providerId;
  List<RemoteBackupMetadata> _history = const [];
  bool _busy = false;
  bool _authenticationRequired = false;
  String? _message;
  int _keepLatest = 3;
  bool _automaticEnabled = false;
  int _automaticDays = 7;
  CloudBackupRuntimeReport? _runtime;

  @override
  void initState() {
    super.initState();
    if (widget.gateway.providers.isNotEmpty) {
      _providerId = widget.gateway.providers.first.id;
      _reload();
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _authenticationRequired = false;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() {
          _authenticationRequired = _isAuthenticationRequired(error);
          _message = _errorText(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload() async {
    final providerId = _providerId;
    if (providerId == null) return;
    await _perform(() async {
      final runtime = widget.gateway is CloudBackupRuntimeGateway
          ? await (widget.gateway as CloudBackupRuntimeGateway).maintainRuntime(
              providerId,
              widget.now().toUtc(),
            )
          : null;
      final results = await Future.wait<Object?>([
        widget.gateway.history(providerId),
        widget.gateway.schedule(providerId),
      ]);
      final rows = results[0]! as List<RemoteBackupMetadata>;
      final schedule = results[1] as CloudBackupScheduleRecord?;
      if (mounted && _providerId == providerId) {
        setState(() {
          _history = rows;
          _automaticEnabled = schedule?.enabled ?? false;
          _automaticDays = _supportedDays(schedule?.interval) ?? 7;
          _runtime = runtime;
          if (runtime?.lastFailure case final failure?) {
            _authenticationRequired = _requiresReconnect(failure);
            _message = _runtimeFailureText(failure);
          }
        });
      }
    });
  }

  Future<void> _create() => _perform(() async {
    final providerId = _providerId!;
    await widget.gateway.createBackup(providerId);
    final runtime = widget.gateway is CloudBackupRuntimeGateway
        ? await (widget.gateway as CloudBackupRuntimeGateway).maintainRuntime(
            providerId,
            widget.now().toUtc(),
          )
        : null;
    final rows = await widget.gateway.history(providerId);
    if (mounted && _providerId == providerId) {
      setState(() {
        _history = rows;
        _runtime = runtime;
        _message = runtime != null && runtime.pendingJobs == 0
            ? '加密備份已完成上傳。'
            : '加密備份已排入上傳；可安全離開此頁。';
      });
    }
  });

  Future<void> _reconnect() => _perform(() async {
    final providerId = _providerId!;
    await widget.gateway.reconnect(providerId);
    final runtime = widget.gateway is CloudBackupRuntimeGateway
        ? await (widget.gateway as CloudBackupRuntimeGateway).maintainRuntime(
            providerId,
            widget.now().toUtc(),
          )
        : null;
    final results = await Future.wait<Object?>([
      widget.gateway.history(providerId),
      widget.gateway.schedule(providerId),
    ]);
    if (mounted && _providerId == providerId) {
      final schedule = results[1] as CloudBackupScheduleRecord?;
      setState(() {
        _history = results[0]! as List<RemoteBackupMetadata>;
        _automaticEnabled = schedule?.enabled ?? false;
        _automaticDays = _supportedDays(schedule?.interval) ?? 7;
        _runtime = runtime;
        _message = runtime != null && runtime.pendingJobs == 0
            ? '雲端帳號已重新連結，待處理備份已完成。'
            : '雲端帳號已重新連結，備份工作已恢復。';
      });
    }
  });

  Future<void> _restore(RemoteBackupMetadata backup) async {
    final result = await showDialog<_RestoreCredential>(
      context: context,
      builder: (context) => const _RestoreCredentialDialog(),
    );
    if (result == null || !mounted) return;
    await _perform(() async {
      await widget.gateway.restore(
        providerId: _providerId!,
        backup: backup,
        credentialKind: result.kind,
        credential: result.credential,
      );
      await widget.onRestored?.call();
      if (mounted) {
        setState(() => _message = '備份已驗證，並交給安全還原流程。');
      }
    });
  }

  Future<void> _retention() => _perform(() async {
    final providerId = _providerId!;
    final plan = await widget.gateway.previewRetention(
      providerId: providerId,
      keepLatest: _keepLatest,
      now: widget.now(),
    );
    if (!mounted) return;
    if (plan.delete.isEmpty) {
      setState(() => _message = '沒有符合清理條件的舊備份。');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('永久刪除舊備份？'),
        content: Text(
          '將保留最新 ${plan.keep.length} 份，永久刪除 ${plan.delete.length} 份。刪除後無法復原。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確認永久刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.gateway.applyRetention(plan);
    final rows = await widget.gateway.history(providerId);
    if (mounted && _providerId == providerId) {
      setState(() {
        _history = rows;
        _message = '舊備份已依預覽結果刪除。';
      });
    }
  });

  Future<void> _configureAutomatic(bool enabled, {int? days}) =>
      _perform(() async {
        final selectedDays = days ?? _automaticDays;
        final interval = Duration(days: selectedDays);
        final now = widget.now().toUtc();
        await widget.gateway.configureSchedule(
          providerId: _providerId!,
          enabled: enabled,
          interval: interval,
          firstDueAt: now.add(interval),
          now: now,
        );
        if (mounted) {
          setState(() {
            _automaticEnabled = enabled;
            _automaticDays = selectedDays;
            _message = enabled ? '自動備份已啟用，會從下一個週期開始。' : '自動備份已停用；已排入的工作不會被刪除。';
          });
        }
      });

  @override
  Widget build(BuildContext context) {
    final providers = widget.gateway.providers;
    final content = <Widget>[
      if (widget.embedded) ...[
        Text('雲端備份', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
      ],
      const Text('備份內容已加密；雲端服務不會取得帳本密碼或救援文字。'),
      if (_message != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_message!, key: const ValueKey('cloud-message')),
        ),
      if (_runtime case final runtime?)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            runtime.pendingJobs == 0
                ? '上傳佇列目前沒有待處理工作。'
                : '尚有 ${runtime.pendingJobs} 份加密備份等待上傳。',
            key: const ValueKey('cloud-runtime-status'),
          ),
        ),
      if (_authenticationRequired &&
          _providerId != null &&
          widget.gateway.canReconnect(_providerId!))
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            key: const ValueKey('cloud-reconnect'),
            onPressed: _busy ? null : _reconnect,
            icon: const Icon(Icons.link),
            label: const Text('重新連結雲端帳號'),
          ),
        ),
      const SizedBox(height: 12),
      if (providers.isEmpty)
        const Text('尚未設定可用的雲端備份服務。')
      else ...[
        DropdownButtonFormField<String>(
          key: const ValueKey('cloud-provider'),
          initialValue: _providerId,
          decoration: const InputDecoration(labelText: '備份服務'),
          items: [
            for (final provider in providers)
              DropdownMenuItem(value: provider.id, child: Text(provider.label)),
          ],
          onChanged: _busy
              ? null
              : (value) {
                  setState(() {
                    _providerId = value;
                    _history = const [];
                    _authenticationRequired = false;
                  });
                  _reload();
                },
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _create,
          child: const Text('立即建立加密備份'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : _reload,
          child: const Text('重新整理歷史'),
        ),
        const Divider(height: 32),
        Text('備份歷史', style: Theme.of(context).textTheme.titleLarge),
        if (_history.isEmpty && !_busy) const Text('目前沒有雲端備份。'),
        for (final backup in _history)
          ListTile(
            key: ValueKey('cloud-backup-${backup.objectId}'),
            title: Text(_dateText(backup.createdAt)),
            subtitle: Text('${backup.byteLength} bytes · ${backup.providerId}'),
            trailing: TextButton(
              onPressed: _busy ? null : () => _restore(backup),
              child: const Text('下載並還原'),
            ),
          ),
        const Divider(height: 32),
        SwitchListTile(
          key: const ValueKey('automatic-backup'),
          contentPadding: EdgeInsets.zero,
          title: const Text('自動加密備份'),
          subtitle: const Text('預設關閉；啟用後從下一個週期開始。'),
          value: _automaticEnabled,
          onChanged: _busy ? null : _configureAutomatic,
        ),
        DropdownButtonFormField<int>(
          key: const ValueKey('automatic-days'),
          initialValue: _automaticDays,
          decoration: const InputDecoration(labelText: '自動備份週期'),
          items: const [
            DropdownMenuItem(value: 1, child: Text('每天')),
            DropdownMenuItem(value: 7, child: Text('每週')),
            DropdownMenuItem(value: 30, child: Text('每 30 天')),
          ],
          onChanged: _busy
              ? null
              : (value) {
                  final days = value ?? 7;
                  if (_automaticEnabled) {
                    _configureAutomatic(true, days: days);
                  } else {
                    setState(() => _automaticDays = days);
                  }
                },
        ),
        const Divider(height: 32),
        DropdownButtonFormField<int>(
          key: const ValueKey('retention-count'),
          initialValue: _keepLatest,
          decoration: const InputDecoration(labelText: '保留最新份數'),
          items: const [
            DropdownMenuItem(value: 1, child: Text('1 份')),
            DropdownMenuItem(value: 3, child: Text('3 份')),
            DropdownMenuItem(value: 5, child: Text('5 份')),
            DropdownMenuItem(value: 10, child: Text('10 份')),
          ],
          onChanged: _busy || _history.isEmpty
              ? null
              : (value) => setState(() => _keepLatest = value ?? 3),
        ),
        OutlinedButton(
          onPressed: _busy || _history.isEmpty ? null : _retention,
          child: const Text('預覽並清理舊備份'),
        ),
      ],
      if (_busy) const LinearProgressIndicator(),
    ];
    if (widget.embedded) return Column(children: content);
    return Scaffold(
      appBar: AppBar(title: const Text('雲端備份')),
      body: ListView(padding: const EdgeInsets.all(16), children: content),
    );
  }
}

bool _requiresReconnect(CloudBackupWorkFailure failure) => switch (failure) {
  CloudBackupWorkFailure.authenticationRequired ||
  CloudBackupWorkFailure.permissionDenied ||
  CloudBackupWorkFailure.quotaExceeded => true,
  _ => false,
};

String _runtimeFailureText(CloudBackupWorkFailure failure) => switch (failure) {
  CloudBackupWorkFailure.authenticationRequired => '雲端登入已失效，請重新連結後續傳。',
  CloudBackupWorkFailure.permissionDenied => '雲端權限不足，請重新連結並確認授權。',
  CloudBackupWorkFailure.quotaExceeded => '雲端空間或額度不足；處理後可重新連結續傳。',
  CloudBackupWorkFailure.throttled => '雲端服務暫時限制請求，工作會保留並稍後重試。',
  CloudBackupWorkFailure.unavailable => '雲端服務暫時無法使用，工作會保留並稍後重試。',
  CloudBackupWorkFailure.uncertainResult => '上次上傳結果不明，將以相同備份識別重試。',
  CloudBackupWorkFailure.integrityRejected => '備份完整性驗證失敗，已停止自動重試。',
  CloudBackupWorkFailure.temporaryLocalFailure => '本機暫時無法處理備份，工作仍保留。',
};

final class _RestoreCredential {
  const _RestoreCredential(this.kind, this.credential);

  final CloudBackupCredentialKind kind;
  final String credential;
}

final class _RestoreCredentialDialog extends StatefulWidget {
  const _RestoreCredentialDialog();

  @override
  State<_RestoreCredentialDialog> createState() =>
      _RestoreCredentialDialogState();
}

final class _RestoreCredentialDialogState
    extends State<_RestoreCredentialDialog> {
  final _controller = TextEditingController();
  var _kind = CloudBackupCredentialKind.password;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('驗證並還原備份'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('使用救援文字'),
          value: _kind == CloudBackupCredentialKind.recoveryKey,
          onChanged: (value) => setState(() {
            _kind = value
                ? CloudBackupCredentialKind.recoveryKey
                : CloudBackupCredentialKind.password;
            _controller.clear();
          }),
        ),
        TextField(
          key: const ValueKey('cloud-restore-credential'),
          controller: _controller,
          obscureText: true,
          decoration: InputDecoration(
            labelText: _kind == CloudBackupCredentialKind.password
                ? '備份的密碼'
                : '備份的救援文字',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_controller.text.isEmpty) return;
          Navigator.pop(context, _RestoreCredential(_kind, _controller.text));
        },
        child: const Text('驗證並繼續'),
      ),
    ],
  );
}

String _dateText(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

int? _supportedDays(Duration? interval) {
  if (interval == null || interval.inHours % 24 != 0) return null;
  final days = interval.inDays;
  return const {1, 7, 30}.contains(days) ? days : null;
}

String _errorText(Object error) => switch (error) {
  CloudBackupProviderException(
    failure: CloudBackupProviderFailure.authenticationRequired,
  ) =>
    '雲端登入已失效，請重新連結後再試。',
  CloudBackupProviderException(
    failure: CloudBackupProviderFailure.quotaExceeded,
  ) =>
    '雲端空間不足，沒有刪除或改動本機帳本。',
  CloudBackupProviderException(failure: CloudBackupProviderFailure.throttled) =>
    '雲端服務暫時限制請求，系統會保留工作供稍後重試。',
  CloudBackupValidationException(
    failure: CloudBackupValidationFailure.credentialRejected,
  ) =>
    '密碼或救援文字不正確，帳本未變更。',
  CloudBackupValidationException() => '備份完整性驗證失敗，已停止操作。',
  _ => '雲端備份目前無法完成；本機帳本未變更。',
};

bool _isAuthenticationRequired(Object error) =>
    error is CloudBackupProviderException &&
    error.failure == CloudBackupProviderFailure.authenticationRequired;
