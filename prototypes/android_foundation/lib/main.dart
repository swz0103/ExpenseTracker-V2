import 'package:flutter/material.dart';

import 'probe_runner.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});
  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final _runner = ProbeRunner();
  bool _busy = false;
  String _status = '尚未在此裝置執行。';
  Future<void> _run() async {
    setState(() {
      _busy = true;
      _status = '正在驗證測試資料…';
    });
    try {
      final result = await _runner.run();
      if (mounted) setState(() => _status = result.join('\n'));
    } catch (_) {
      if (mounted) setState(() => _status = '驗證未通過，未自動重設資料或金鑰。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '記帳 V2 地基驗證',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(title: const Text('地基驗證')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('僅使用固定測試資料，尚非日常記帳版本。'),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _run,
                child: Text(_busy ? '驗證中…' : '執行裝置驗證'),
              ),
              const SizedBox(height: 24),
              Text(_status),
            ],
          ),
        ),
      ),
    );
  }
}
