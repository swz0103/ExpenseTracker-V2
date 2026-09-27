import 'dart:async';

import 'package:accounts/accounts.dart';
import 'package:backup_envelope_probe/envelope.dart';
import 'package:categories/categories.dart';
import 'package:tags/tags.dart';
import 'package:merchants/merchants.dart';
import 'package:flutter/material.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';

import 'platform_services.dart';
import 'preview_engine.dart';

part 'category_screen.dart';
part 'tag_screen.dart';
part 'merchant_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    PreviewApp(engine: createEngine(), documents: AndroidBackupDocuments()),
  );
}

class PreviewApp extends StatelessWidget {
  const PreviewApp({super.key, required this.engine, required this.documents});
  final Future<PreviewEngine> engine;
  final BackupDocuments documents;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '記帳 V2 試用版',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xff25675c),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    home: PreviewHome(engine: engine, documents: documents),
  );
}

enum _Page {
  loading,
  setup,
  recovery,
  locked,
  upgrade,
  categories,
  tags,
  merchants,
  home,
  account,
  posting,
  restore,
  blocked,
}

class PreviewHome extends StatefulWidget {
  const PreviewHome({super.key, required this.engine, required this.documents});
  final Future<PreviewEngine> engine;
  final BackupDocuments documents;
  @override
  State<PreviewHome> createState() => _PreviewHomeState();
}

class _PreviewHomeState extends State<PreviewHome> with WidgetsBindingObserver {
  PreviewEngine? _engine;
  _Page _page = _Page.loading;
  bool _busy = false, _saved = false, _useRecovery = false;
  String? _message, _imported;
  CreatedBackup? _draft;
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _date = TextEditingController();
  final _credential = TextEditingController();
  String _currency = 'TWD';
  AccountKind _kind = AccountKind.cash;
  bool _income = false;
  String _categoryId = '';
  CategoryCatalog? _catalog;
  TagCatalog? _tagCatalog;
  MerchantCatalog? _merchantCatalog;
  String _merchantId = '';
  final _entryMerchants = <PublicId, String>{};
  final _selectedTags = <PublicId>{};
  final _entryTags = <PublicId, String>{};
  final _entryCategories = <PublicId, String>{};
  PublicId? _accountId;
  List<AccountSummary> _accounts = [];
  List<LedgerEntry> _entries = [];
  bool _hasMore = false;
  bool _hasSafety = false;
  Account? _pendingAccount;
  Posting? _pendingPosting;
  String? _inputSignature;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final engine = await widget.engine;
      final exists = await engine.hasProfile();
      if (!mounted) return;
      setState(() {
        _engine = engine;
        _page = exists ? _Page.locked : _Page.setup;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _page = _Page.blocked;
          _message = '無法讀取設定。原資料已保留，請勿清除 App 資料。';
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _lock();
  }

  void _clear() {
    for (final c in [_password, _confirm, _name, _amount, _date, _credential]) {
      c.clear();
    }
    _draft = null;
    _saved = false;
    _accounts = [];
    _entries = [];
    _catalog = null;
    _tagCatalog = null;
    _merchantCatalog = null;
    _entryMerchants.clear();
    _selectedTags.clear();
    _entryTags.clear();
    _categoryId = '';
    _merchantId = '';
    _entryCategories.clear();
    _pendingAccount = null;
    _pendingPosting = null;
    _inputSignature = null;
  }

  void _lock() {
    final engine = _engine;
    if (engine == null) return;
    unawaited(
      engine.lock().catchError((Object _) {
        if (mounted) {
          setState(() {
            _page = _Page.blocked;
            _message = '資料庫關閉未能完成，已停止操作。請保留現有資料。';
          });
        }
      }),
    );
    if (!mounted) return;
    setState(() {
      _clear();
      _page = _Page.locked;
      _message = null;
    });
    unawaited(_resolveLockedPage());
  }

  Future<void> _resolveLockedPage() async {
    try {
      final exists = await _engine!.hasProfile();
      if (mounted && !_engine!.isUnlocked && !_busy) {
        setState(() => _page = exists ? _Page.locked : _Page.setup);
      }
    } catch (_) {
      if (mounted) setState(() => _page = _Page.blocked);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // The view is being disposed; the engine retains a failed close future and
    // refuses subsequent sessions. There is no remaining view to notify here.
    unawaited(_engine?.lock().catchError((Object _) {}));
    for (final c in [_password, _confirm, _name, _amount, _date, _credential]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _message = _error(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_page == _Page.locked) await _resolveLockedPage();
      }
    }
  }

  Future<void> _refresh() async {
    final accounts = await _engine!.accounts();
    final entries = await _engine!.entries();
    final catalog = await _engine!.categories();
    final labels = await _categoryLabels(entries, catalog);
    final tagCatalog = _engine!.schemaVersion >= 6
        ? await _engine!.tags()
        : null;
    final tagLabels = await _tagLabels(entries, tagCatalog);
    final merchantCatalog = _engine!.schemaVersion >= 7
        ? await _engine!.merchants()
        : null;
    final merchantLabels = await _merchantLabels(entries, merchantCatalog);
    final safety = await _engine!.hasSafetyCopy();
    if (!mounted || !_engine!.isUnlocked) return;
    setState(() {
      _accounts = accounts;
      _entries = entries;
      _catalog = catalog;
      _tagCatalog = tagCatalog;
      _merchantCatalog = merchantCatalog;
      _entryMerchants
        ..clear()
        ..addAll(merchantLabels);
      _entryTags
        ..clear()
        ..addAll(tagLabels);
      _entryCategories
        ..clear()
        ..addAll(labels);
      _hasMore = entries.length == 30;
      _hasSafety = safety;
      _page = _imported == null ? _Page.home : _Page.restore;
    });
  }

  Future<void> _unlock({bool upgrade = false}) => _perform(() async {
    try {
      if (upgrade) {
        await _engine!.upgrade(_password.text);
      } else {
        await _engine!.unlock(_password.text);
      }
    } on PreviewUpgradeRequired {
      if (mounted) setState(() => _page = _Page.upgrade);
      return;
    }
    _password.clear();
    await _refresh();
  });
  Future<void> _prepare() => _perform(() async {
    if (_password.text != _confirm.text) throw const FormatException();
    final draft = await _engine!.prepareSetup(_password.text);
    if (mounted) {
      setState(() {
        _draft = draft;
        _page = _Page.recovery;
      });
    }
  });
  Future<void> _finish() => _perform(() async {
    await _engine!.finishSetup(_draft!, _password.text, savedRecovery: _saved);
    _password.clear();
    _confirm.clear();
    _draft = null;
    await _refresh();
  });
  void _edit(_Page page) {
    setState(() {
      _page = page;
      _message = null;
      _name.clear();
      _amount.text = page == _Page.account ? '0' : '';
      final now = DateTime.now();
      _date.text = BusinessDate(now.year, now.month, now.day).toString();
      _pendingPosting = null;
      _pendingAccount = null;
      _inputSignature = null;
      _categoryId = '';
      _merchantId = '';
      _selectedTags.clear();
      _accountId = _accounts
          .where((a) => a.account.state == AccountState.active)
          .firstOrNull
          ?.account
          .id;
    });
  }

  Future<void> _copyPosting(PublicId id) => _perform(() async {
    await _refresh();
    final copy = await _engine!.preparePostingCopy(id);
    if (!mounted || !_engine!.isUnlocked) return;
    _edit(_Page.posting);
    setState(() {
      _income = copy.income;
      _accountId = copy.account.id;
      _categoryId = copy.categoryId?.value ?? '';
      _merchantId = copy.merchant?.id.value ?? '';
      _selectedTags.addAll(copy.tags.map((tag) => tag.id));
      _date.clear();
      _message = copy.omittedMetadata
          ? '已沿用可用欄位；部分分類、標籤或商家需重新選擇。請輸入本次金額與日期。'
          : '已沿用帳戶、分類、標籤與商家；請輸入本次金額與日期。';
    });
  });

  PostingAccount _ref(Account a) => PostingAccount(
    id: a.id,
    workspace: a.workspace,
    currency: a.currency,
    expectedVersion: a.version,
  );
  Future<void> _saveAccount() => _perform(() async {
    final signature =
        '$_kind|$_currency|${_name.text}|${_amount.text}|${_date.text}';
    if (_inputSignature != signature) {
      final a = Account.open(
        id: PublicId.generate(),
        workspace: _engine!.workspace,
        name: _name.text,
        kind: _kind,
        currency: Currency(_currency, _currency == 'JPY' ? 0 : 2),
        openedOn: BusinessDate.parse(_date.text),
      );
      final p = Posting.opening(
        id: PublicId.generate(),
        operation: OperationKey(a.workspace, OperationId(PublicId.generate())),
        date: a.openedOn,
        account: _ref(a),
        amount: Money.parse(a.currency, _amount.text),
      );
      _pendingAccount = a;
      _pendingPosting = p;
      _inputSignature = signature;
    }
    await _engine!.createAccount(_pendingAccount!, _pendingPosting!);
    await _refresh();
  });
  Future<void> _savePosting() => _perform(() async {
    final a = _accounts.firstWhere((a) => a.account.id == _accountId).account;
    final category = _categoryId.isEmpty
        ? null
        : _catalog!.get(PublicId.parse(_categoryId));
    final merchant = _merchantId.isEmpty
        ? null
        : _merchantCatalog!.get(PublicId.parse(_merchantId));
    final tags = _selectedTags.map((id) => _tagCatalog!.get(id)).toList()
      ..sort((a, b) => a.id.value.compareTo(b.id.value));
    final signature =
        '${a.id}|$_income|${_amount.text}|${_date.text}|$_categoryId|${category?.version}|${merchant?.id}:${merchant?.version}|${tags.map((t) => '${t.id}:${t.version}').join(',')}';
    if (_inputSignature != signature) {
      final factory = _income ? Posting.income : Posting.expense;
      _pendingPosting = factory(
        id: PublicId.generate(),
        operation: OperationKey(a.workspace, OperationId(PublicId.generate())),
        date: BusinessDate.parse(_date.text),
        account: _ref(a),
        amount: Money.parse(a.currency, _amount.text),
        allocations: category == null
            ? const []
            : [
                Allocation(
                  category.id,
                  Money.parse(a.currency, _amount.text),
                  expectedCategoryVersion: category.version,
                ),
              ],
      );
      _inputSignature = signature;
    }
    await _engine!.post(
      _pendingPosting!,
      tags: [for (final tag in tags) TagSelection(tag.id, tag.version)],
      merchant: merchant == null
          ? null
          : MerchantSelection(merchant.id, merchant.version),
    );
    await _refresh();
  });
  Future<void> _export({bool previous = false}) => _perform(() async {
    final encrypted = previous
        ? await _engine!.exportPreviousBackup()
        : await _engine!.exportBackup();
    final saved = await widget.documents.save(encrypted);
    if (mounted) {
      setState(() => _message = saved ? '加密備份已儲存，並讀回核對成功。' : '已取消儲存。');
    }
  });
  Future<void> _openImport() => _perform(() async {
    final encrypted = await widget.documents.open();
    if (!mounted || encrypted == null) return;
    setState(() {
      _imported = encrypted;
      if (_engine!.isUnlocked) _page = _Page.restore;
    });
  });
  Future<void> _restore() => _perform(() async {
    await _engine!.importBackup(
      _imported!,
      _credential.text,
      recovery: _useRecovery,
    );
    _credential.clear();
    _imported = null;
    await _refresh();
    if (mounted) setState(() => _message = '還原完成。之後備份沿用此 App 設定的密碼與救援文字。');
  });
  Future<void> _more() => _perform(() async {
    final next = await _engine!.entries(before: _entries.last);
    final labels = await _categoryLabels(next, _catalog!);
    final tagLabels = await _tagLabels(next, _tagCatalog);
    final merchantLabels = await _merchantLabels(next, _merchantCatalog);
    if (mounted && _engine!.isUnlocked) {
      setState(() {
        _entries.addAll(next);
        _entryCategories.addAll(labels);
        _entryTags.addAll(tagLabels);
        _entryMerchants.addAll(merchantLabels);
        _hasMore = next.length == 30;
      });
    }
  });

  Future<Map<PublicId, String>> _merchantLabels(
    List<LedgerEntry> entries,
    MerchantCatalog? catalog,
  ) async {
    if (catalog == null) return {};
    final result = <PublicId, String>{};
    for (final entry in entries) {
      final ref = await _engine!.merchantFor(entry.id);
      if (ref != null) {
        result[entry.id] = _merchantLabel(catalog, catalog.get(ref.id));
      }
    }
    return result;
  }

  Future<Map<PublicId, String>> _tagLabels(
    List<LedgerEntry> entries,
    TagCatalog? catalog,
  ) async {
    if (catalog == null) return {};
    final result = <PublicId, String>{};
    for (final entry in entries) {
      final refs = await _engine!.tagsFor(entry.id);
      if (refs.isNotEmpty) {
        result[entry.id] = refs
            .map((r) => '#${_tagLabel(catalog, catalog.get(r.id))}')
            .join('、');
      }
    }
    return result;
  }

  Future<Map<PublicId, String>> _categoryLabels(
    List<LedgerEntry> entries,
    CategoryCatalog catalog,
  ) async {
    final result = <PublicId, String>{};
    for (final entry in entries) {
      if (entry.kind == PostingKind.opening) continue;
      final allocations = await _engine!.allocations(entry.id);
      result[entry.id] = allocations.isEmpty
          ? '未分類'
          : allocations
                .map((a) => _categoryLabel(catalog, catalog.get(a.categoryId)))
                .join('、');
    }
    return result;
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool secret = false,
    int? length,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: controller,
      enabled: !_busy,
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: !secret,
      maxLength: length,
      decoration: InputDecoration(labelText: label),
      onSubmitted: secret && _page == _Page.locked ? (_) => _unlock() : null,
    ),
  );
  Widget _button(String label, VoidCallback? onPressed) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: FilledButton(
      onPressed: _busy ? null : onPressed,
      child: Text(label),
    ),
  );
  Widget _back() => TextButton(
    onPressed: _busy
        ? null
        : () => setState(() {
            _page = _Page.home;
            _imported = null;
            _credential.clear();
            _message = null;
          }),
    child: const Text('返回帳本'),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('記帳 V2'),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(3),
        child: SizedBox(
          height: 3,
          child: _busy ? const LinearProgressIndicator() : null,
        ),
      ),
      actions: [
        if (_engine?.isUnlocked ?? false)
          IconButton(
            onPressed: _lock,
            tooltip: '鎖定',
            icon: const Icon(Icons.lock_outline),
          ),
      ],
    ),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('最小試用版', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_message!, key: const Key('message')),
                ),
              ..._content(),
            ],
          ),
        ),
      ),
    ),
  );
  List<Widget> _content() {
    switch (_page) {
      case _Page.upgrade:
        return [
          Text('更新帳本', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          const Text(
            '使用這個版本前，需要更新此帳本。系統會先保存並驗證加密備份，再更新資料；原有交易、備份密碼與救援文字都會保留。若中斷，重新解鎖後可以繼續。',
          ),
          const SizedBox(height: 16),
          _button('備份並更新', () => _unlock(upgrade: true)),
          TextButton(
            onPressed: _busy ? null : _lock,
            child: const Text('稍後再更新'),
          ),
        ];
      case _Page.merchants:
        return [
          _MerchantScreen(
            engine: _engine!,
            catalog: _merchantCatalog!,
            onDone: () => _perform(_refresh),
          ),
        ];
      case _Page.tags:
        return [
          _TagScreen(
            engine: _engine!,
            catalog: _tagCatalog!,
            onDone: () => _perform(_refresh),
          ),
        ];
      case _Page.categories:
        return [
          _CategoryScreen(
            engine: _engine!,
            catalog: _catalog!,
            onDone: () => _perform(_refresh),
          ),
        ];
      case _Page.loading:
        return [const Center(child: CircularProgressIndicator())];
      case _Page.blocked:
        return [const Text('設定或儲存發生問題，已停止開啟帳本。請保留現有資料與加密備份。')];
      case _Page.setup:
        return [
          Text('建立你的帳本', style: Theme.of(context).textTheme.headlineSmall),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '資料保存在手機。請設定至少 12 個字元的密碼，用於解鎖及匯出備份。\n這是功能試用版；請先用測試資料驗收。',
            ),
          ),
          _field('設定密碼（至少 12 個字元）', _password, secret: true),
          _field('再次輸入密碼', _confirm, secret: true),
          _button('產生救援文字', _prepare),
        ];
      case _Page.recovery:
        return [
          Text('保存救援文字', style: Theme.of(context).textTheme.headlineSmall),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('請另外保存下列文字。它能解開你匯出的加密備份；單有文字不能找回尚未備份的資料。'),
          ),
          SelectableText(
            _draft?.recoveryKey ?? '',
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('我已另外保存救援文字'),
            value: _saved,
            onChanged: _busy
                ? null
                : (v) => setState(() => _saved = v ?? false),
          ),
          _button('完成設定', _saved ? _finish : null),
        ];
      case _Page.locked:
        return [
          Text('解鎖帳本', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),
          _field('密碼', _password, secret: true),
          _button('解鎖', _unlock),
          if (_imported != null) const Text('已選取加密備份；解鎖後繼續確認還原。'),
          const Text('救援文字用於加密備份還原。忘記此密碼時，可在新的安裝中設定新密碼後，再匯入已保存的備份。'),
        ];
      case _Page.account:
        return [
          Text('新增帳戶', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          _field('帳戶名稱', _name, length: 100),
          DropdownButtonFormField<AccountKind>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: '類型'),
            items: const [
              DropdownMenuItem(value: AccountKind.cash, child: Text('現金')),
              DropdownMenuItem(value: AccountKind.bank, child: Text('銀行')),
            ],
            onChanged: _busy ? null : (v) => setState(() => _kind = v!),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _currency,
            decoration: const InputDecoration(labelText: '幣別'),
            items: [
              for (final c in ['TWD', 'USD', 'JPY'])
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: _busy ? null : (v) => setState(() => _currency = v!),
          ),
          const SizedBox(height: 14),
          _field('期初餘額', _amount),
          _field('起始日期（YYYY-MM-DD）', _date),
          _button('建立帳戶', _saveAccount),
          _back(),
        ];
      case _Page.posting:
        return [
          Text('記一筆', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('支出')),
              ButtonSegment(value: true, label: Text('收入')),
            ],
            selected: {_income},
            onSelectionChanged: _busy
                ? null
                : (v) => setState(() {
                    _income = v.single;
                    _categoryId = '';
                    _merchantId = '';
                    _selectedTags.clear();
                  }),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<PublicId>(
            initialValue: _accountId,
            decoration: const InputDecoration(labelText: '帳戶'),
            items: [
              for (final s in _accounts.where(
                (s) => s.account.state == AccountState.active,
              ))
                DropdownMenuItem(
                  value: s.account.id,
                  child: Text('${s.account.name} · ${s.account.currency.code}'),
                ),
            ],
            onChanged: _busy ? null : (v) => setState(() => _accountId = v),
          ),
          const SizedBox(height: 14),
          _field('金額（正數）', _amount),
          _field('日期（YYYY-MM-DD）', _date),
          DropdownButtonFormField<String>(
            key: ValueKey('posting-category-$_income'),
            initialValue: _categoryId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '分類'),
            items: [
              const DropdownMenuItem(value: '', child: Text('未分類')),
              for (final c in _catalog!.categories.where(
                (c) =>
                    !c.archived &&
                    c.kind ==
                        (_income ? CategoryKind.income : CategoryKind.expense),
              ))
                DropdownMenuItem(
                  value: c.id.value,
                  child: Text(
                    _categoryLabel(_catalog!, c),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _categoryId = value ?? ''),
          ),
          const SizedBox(height: 14),
          if (_merchantCatalog != null)
            _MerchantPicker(
              key: ValueKey('merchant-picker-$_income'),
              catalog: _merchantCatalog!,
              selected: _merchantId,
              enabled: !_busy,
              onChanged: (value) => setState(() => _merchantId = value),
            ),
          if (_tagCatalog != null &&
              _tagCatalog!.tags.any((t) => !t.archived)) ...[
            const Text('標籤（可複選，最多 16 個）'),
            Wrap(
              spacing: 8,
              children: [
                for (final tag in _tagCatalog!.tags.where((t) => !t.archived))
                  FilterChip(
                    label: Text(tag.name),
                    selected: _selectedTags.contains(tag.id),
                    onSelected: _busy
                        ? null
                        : (selected) => setState(() {
                            if (!selected) {
                              _selectedTags.remove(tag.id);
                            } else if (_selectedTags.length < 16) {
                              _selectedTags.add(tag.id);
                            } else {
                              _message = '一筆交易最多選擇 16 個標籤。';
                            }
                          }),
                  ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          _button('儲存收支', _savePosting),
          _back(),
        ];
      case _Page.restore:
        return [
          Text('還原加密備份', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          const Text(
            '會以備份內容取代目前帳本。系統先保存並驗證原帳本的加密安全副本；原世代也會保留。\n\n輸入該備份原有的密碼或救援文字。還原後的新備份使用此 App 設定的密碼與救援文字。',
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('使用救援文字'),
            value: _useRecovery,
            onChanged: _busy
                ? null
                : (v) => setState(() {
                    _useRecovery = v;
                    _credential.clear();
                  }),
          ),
          _field(_useRecovery ? '備份的救援文字' : '備份的密碼', _credential, secret: true),
          _button('確認取代並還原', _restore),
          _back(),
        ];
      case _Page.home:
        return [
          Text('我的帳本', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          if (_accounts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('先新增一個帳戶，就可以開始記帳。'),
            ),
          for (final s in _accounts)
            Card(
              child: ListTile(
                title: Text(s.account.name),
                subtitle: Text(
                  s.account.kind == AccountKind.cash ? '現金' : '銀行',
                ),
                trailing: Text(
                  '${s.account.currency.code} ${moneyText(s.balance)}',
                ),
              ),
            ),
          const SizedBox(height: 16),
          _button(
            '記一筆',
            _accounts.any((s) => s.account.state == AccountState.active)
                ? () => _edit(_Page.posting)
                : null,
          ),
          OutlinedButton(
            onPressed: _busy ? null : () => _edit(_Page.account),
            child: const Text('新增帳戶'),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() => _page = _Page.categories),
            child: const Text('管理分類'),
          ),
          if (_tagCatalog != null)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _page = _Page.tags),
              child: const Text('管理標籤'),
            ),
          if (_merchantCatalog != null)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _page = _Page.merchants),
              child: const Text('管理商家'),
            ),
          const SizedBox(height: 24),
          Text('最近交易', style: Theme.of(context).textTheme.titleLarge),
          if (_entries.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('尚無交易')),
          for (final e in _entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${_kindLabel(e.kind)} · ${_accounts.where((a) => a.account.id == e.accountId).firstOrNull?.account.name ?? '帳戶'}',
              ),
              subtitle: Text(
                '${e.date}${_entryCategories[e.id] == null ? '' : ' · ${_entryCategories[e.id]}'}${_entryTags[e.id] == null ? '' : ' · ${_entryTags[e.id]}'}${_entryMerchants[e.id] == null ? '' : ' · ${_entryMerchants[e.id]}'}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${e.amount.currency.code} ${moneyText(e.amount)}'),
                  if ([
                    PostingKind.income,
                    PostingKind.expense,
                  ].contains(e.kind))
                    PopupMenuButton<String>(
                      key: ValueKey('entry-actions-${e.id}'),
                      tooltip: '交易操作',
                      enabled: !_busy,
                      onSelected: (_) => _copyPosting(e.id),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'copy',
                          child: Text('再記一筆類似交易'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          if (_hasMore)
            TextButton(
              onPressed: _busy ? null : _more,
              child: const Text('載入更多'),
            ),
          const Divider(),
          if (_hasSafety)
            OutlinedButton(
              onPressed: _busy ? null : () => _export(previous: true),
              child: const Text('匯出最近一次還原前副本'),
            ),
          OutlinedButton(
            onPressed: _busy ? null : _export,
            child: const Text('匯出加密備份'),
          ),
          TextButton(
            onPressed: _busy ? null : _openImport,
            child: const Text('從檔案還原'),
          ),
          const SizedBox(height: 16),
          const Text(
            '目前上限：32 個帳戶、5,000 筆交易（含期初）、256 個分類、256 個標籤、256 個商家。交易修改／刪除、轉帳與報表尚未開放。',
            style: TextStyle(color: Colors.grey),
          ),
        ];
    }
  }
}

String moneyText(Money money) {
  final digits = money.minorUnits.abs().toString().padLeft(
    money.currency.scale + 1,
    '0',
  );
  final scale = money.currency.scale;
  return '${money.minorUnits.isNegative ? '-' : ''}${scale == 0 ? digits : '${digits.substring(0, digits.length - scale)}.${digits.substring(digits.length - scale)}'}';
}

String _kindLabel(PostingKind kind) => switch (kind) {
  PostingKind.opening => '期初',
  PostingKind.income => '收入',
  PostingKind.expense => '支出',
  PostingKind.transfer => '轉帳',
};
String _error(Object error) => switch (error) {
  MerchantException(code: MerchantError.versionConflict) =>
    '商家已變更，請返回帳本重新整理後再試。',
  MerchantException() => '請檢查商家名稱、別名或合併目標；別名不可重複，封存商家不能用於新交易。',
  TagException(code: TagError.versionConflict) => '標籤已變更，請返回帳本重新整理後再試。',
  TagException() => '請檢查標籤名稱與合併目標；封存或已合併的標籤不能用於新交易。',
  CategoryException(code: CategoryError.hasChildren) => '請先處理子分類，再進行這項操作。',
  CategoryException(code: CategoryError.versionConflict) =>
    '分類已變更，請返回帳本重新載入後再試。',
  CategoryException() => '請檢查分類名稱、收支類型及上層分類；已封存的分類不能用於新交易。',
  PreviewLocked() => '已鎖定，請重新解鎖後查看結果。',
  PreviewBusy() => '前一項操作尚未完成，請稍候。',
  PreviewCapacity() => '已達試用版容量上限，請先匯出備份。',
  MoneyException() => '金額格式、精度或大小不符。請輸入該幣別可接受的金額。',
  AccountException() => '帳戶或日期不符：日期不可早於帳戶起始日，名稱不能空白。',
  LedgerException() => '請檢查帳戶與金額；收支必須是正數。',
  BackupException() => '密碼／救援文字不符、檔案損壞，或設定密碼不足 12 個字元。',
  FormatException() => '請確認日期為 YYYY-MM-DD，兩次設定密碼相同。',
  PreviewInvalid() => '設定或備份不符合試用版支援範圍。原資料已保留。',
  _ => '操作未能完成。請保留原資料與備份，解鎖後確認結果；不要清除 App 資料。',
};
