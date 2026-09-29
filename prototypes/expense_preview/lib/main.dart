import 'transfer_summary.dart';

import 'dart:async';

import 'package:accounts/accounts.dart';
import 'package:backup_envelope_probe/envelope.dart';
import 'package:budgets/budgets.dart';
import 'package:recurring_transactions/recurring_transactions.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:categories/categories.dart';
import 'package:data_exchange/data_exchange.dart';
import 'package:tags/tags.dart';
import 'package:merchants/merchants.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show TextInputFormatter, FilteringTextInputFormatter, PlatformException;
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:reports/reports.dart';
import 'package:ledger_generation_probe/ledger_store.dart';

import 'platform_services.dart';
import 'app_pin.dart';
import 'amount_input_field.dart';
import 'split_allocation_dialog.dart';
import 'business_date_input_field.dart';
import 'l10n/app_localizations.dart';
import 'preview_engine.dart';
import 'money_view.dart';
import 'privacy_presentation.dart';
export 'privacy_presentation.dart' show moneyText;

part 'category_screen.dart';
part 'split_entry.dart';
part 'refund_entry.dart';
part 'reversal_entry.dart';
part 'correction_entry.dart';
part 'tombstone_entry.dart';
part 'note_entry.dart';
part 'activity_dialog.dart';
part 'tag_screen.dart';
part 'merchant_screen.dart';
part 'search_screen.dart';
part 'monthly_report_screen.dart';
part 'budget_screen.dart';
part 'recurring_screen.dart';
part 'card_statement_screen.dart';
part 'simple_import_screen.dart';
part 'simple_export_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    PreviewApp(
      engine: createEngine(),
      documents: AndroidBackupDocuments(),
      deviceUnlock: AndroidDeviceUnlockStore(),
      appPin: VerifiedAppPinStore(AndroidPinRecordStore()),
      recurringReminder: AndroidRecurringReminderService(),
    ),
  );
}

class PreviewApp extends StatefulWidget {
  const PreviewApp({
    super.key,
    required this.engine,
    required this.documents,
    this.deviceUnlock,
    this.appPin,
    this.recurringReminder,
  });
  final Future<PreviewEngine> engine;
  final BackupDocuments documents;
  final DeviceUnlockStore? deviceUnlock;
  final AppPinStore? appPin;
  final RecurringReminderService? recurringReminder;
  @override
  State<PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<PreviewApp> {
  final _routes = _LockRoutes();
  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorObservers: [_routes],
    locale: const Locale('zh', 'TW'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xff25675c),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    home: PreviewHome(
      engine: widget.engine,
      documents: widget.documents,
      deviceUnlock: widget.deviceUnlock,
      appPin: widget.appPin,
      recurringReminder: widget.recurringReminder,
      onLock: _routes.cancel,
    ),
  );
}

/// Tracks only transient routes. Keep exiting routes until their transition
/// finishes so a lock also hides a popup that was just confirmed or dismissed.
final class _LockRoutes extends NavigatorObserver {
  final _popups = <PopupRoute<dynamic>>{};

  void _track(Route<dynamic>? route) {
    if (route is PopupRoute<dynamic> && _popups.add(route)) {
      unawaited(
        route.completed.then((_) {
          _popups.remove(route);
        }),
      );
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _track(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _track(newRoute);

  void cancel() {
    final owner = navigator;
    if (owner == null) return;
    for (final route in _popups.toList().reversed) {
      if (route.navigator != owner) continue;
      // Do not show private dropdown content during its exit animation.
      route.offstage = true;
      if (route.isActive) owner.removeRoute(route);
    }
  }
}

enum _Page {
  loading,
  setup,
  recovery,
  locked,
  pinSetup,
  pinDisable,
  upgrade,
  categories,
  tags,
  merchants,
  search,
  monthlyReport,
  budgets,
  recurring,
  cardStatements,
  home,
  account,
  cardPurchase,
  cardPayment,
  posting,
  restore,
  simpleImport,
  simpleExport,
  blocked,
}

class PreviewHome extends StatefulWidget {
  const PreviewHome({
    super.key,
    required this.engine,
    required this.documents,
    this.deviceUnlock,
    this.appPin,
    this.recurringReminder,
    required this.onLock,
  });
  final Future<PreviewEngine> engine;
  final BackupDocuments documents;
  final DeviceUnlockStore? deviceUnlock;
  final AppPinStore? appPin;
  final RecurringReminderService? recurringReminder;
  final VoidCallback onLock;
  @override
  State<PreviewHome> createState() => _PreviewHomeState();
}

class _PreviewHomeState extends State<PreviewHome> with WidgetsBindingObserver {
  void _updateSimpleImport(VoidCallback change) => setState(change);
  void _updateSimpleExport(VoidCallback change) => setState(change);
  PreviewEngine? _engine;
  _Page _page = _Page.loading;
  bool _busy = false, _saved = false, _useRecovery = false;
  bool _rememberDevice = false, _deviceUnlockEnabled = false;
  bool _pinEnabled = false;
  bool _devicePromptActive = false;
  String? _message, _imported;
  bool _simpleImportSelected = false;
  SimpleTransactionBatch? _simpleImportBatch;
  SimpleImportReview? _simpleImportReview;
  final _simpleImportMapping = <PublicId, PublicId>{};
  bool _simpleExportSelected = false;
  String? _simpleExportFormat;
  SimpleExportReview? _simpleExportReview;
  CreatedBackup? _draft;
  final _scroll = ScrollController(keepScrollOffset: false);
  final _password = TextEditingController();
  final _pin = TextEditingController();
  final _pinConfirm = TextEditingController();
  final _confirm = TextEditingController();
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _cardClosingDay = TextEditingController(text: '30');
  final _cardDueDay = TextEditingController(text: '15');
  final _cardLimit = TextEditingController();
  final _fee = TextEditingController();
  final _received = TextEditingController();
  bool _transfer = false;
  RefundStatus? _refund;
  EntrySubmission? _reversal;
  EntrySubmission? _correction;
  PublicId? _noteTarget;
  int _noteRevision = 0;
  final _noteText = TextEditingController();
  final _reversalReason = TextEditingController();
  final _correctionReason = TextEditingController();
  PublicId? _destinationId;
  final _date = TextEditingController();
  final _credential = TextEditingController();
  String _currency = 'TWD';
  AccountKind _kind = AccountKind.cash;
  bool _income = false;
  String _categoryId = '';
  bool _split = false;
  final _splitRows = <_SplitRow>[];
  CategoryCatalog? _catalog;
  TagCatalog? _tagCatalog;
  MerchantCatalog? _merchantCatalog;
  String _merchantId = '';
  final _entryMerchants = <PublicId, String>{};
  final _selectedTags = <PublicId>{};
  final _entryTags = <PublicId, String>{};
  final _entryCategories = <PublicId, List<LedgerAllocation>>{};
  PublicId? _accountId;
  List<AccountSummary> _accounts = [];
  List<LedgerEntry> _entries = [];
  List<LedgerEntry> _deletedEntries = [];
  MonthlyReport? _monthlyReport;
  bool _monthlyOverflow = false;
  int? _recurringDueCount;
  bool _recurringReminderError = false;
  int _recurringReminderRequest = 0;
  AssetReport? _assetReport;
  bool _assetOverflow = false;
  PrivacyMode _privacy = PrivacyMode.hidden;
  bool _forceHidden = false;
  bool _hasMore = false;
  bool _hasMoreDeleted = false;
  bool _hasSafety = false;
  bool _hasUpgradeSafety = false;
  Account? _pendingAccount;
  Posting? _pendingPosting;
  CreditCardTerms? _pendingCardTerms;
  String? _inputSignature;
  EntryDraft? _entryDraft;
  bool _draftUnreadable = false;
  Future<void> _draftSaveTail = Future.value();
  Future<void>? _lockBarrier;
  Object? _draftSaveError;
  int _viewEpoch = 0, _draftWrites = 0;
  bool get _postingFrozen =>
      (_page == _Page.posting ||
          _page == _Page.cardPurchase ||
          _page == _Page.cardPayment) &&
      _entryDraft?.isPrepared == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final engine = await widget.engine;
      _engine = engine;
      final exists = await engine.hasProfile();
      final safety = await _availableLockedSafetyCopy(engine);
      final upgradeSafety = await _availableLockedUpgradeCopy(engine);
      var deviceEnabled = false;
      var pinEnabled = false;
      try {
        deviceEnabled =
            exists && (await widget.deviceUnlock?.isEnabled() ?? false);
      } catch (_) {
        // Device convenience unlock must never prevent password recovery.
      }
      if (deviceEnabled && widget.appPin != null) {
        try {
          pinEnabled = await widget.appPin!.isEnabled();
        } catch (_) {
          // An unreadable PIN state must not expose the device-only shortcut.
          deviceEnabled = false;
        }
      }
      if (!mounted) return;
      setState(() {
        _engine = engine;
        _hasSafety = safety;
        _hasUpgradeSafety = upgradeSafety;
        _deviceUnlockEnabled = deviceEnabled;
        _pinEnabled = pinEnabled;
        _page = exists ? _Page.locked : _Page.setup;
      });
    } catch (_) {
      if (mounted) {
        final safety = _engine == null
            ? false
            : await _availableLockedSafetyCopy(_engine!);
        final upgradeSafety = _engine == null
            ? false
            : await _availableLockedUpgradeCopy(_engine!);
        if (!mounted) return;
        setState(() {
          _hasSafety = safety;
          _hasUpgradeSafety = upgradeSafety;
          _page = _Page.blocked;
          _message = '無法讀取設定。原資料已保留，請勿清除 App 資料。';
        });
      }
    }
  }

  Future<bool> _availableLockedSafetyCopy(PreviewEngine engine) async {
    try {
      return await engine.hasLockedSafetyCopy();
    } catch (_) {
      // An optional copy must not prevent a healthy profile from unlocking.
      return false;
    }
  }

  Future<bool> _availableLockedUpgradeCopy(PreviewEngine engine) async {
    try {
      return await engine.hasLockedUpgradeCopy();
    } catch (_) {
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android's authentication sheet can briefly remove window focus. The
    // financial view is hidden during enrollment and already locked for read.
    // A real background transition (paused/hidden) must still lock immediately.
    if (state == AppLifecycleState.inactive && _devicePromptActive) return;
    if (state != AppLifecycleState.resumed) _lock();
  }

  Future<T> _withDevicePrompt<T>(Future<T> Function() operation) async {
    final epoch = _viewEpoch;
    _devicePromptActive = true;
    try {
      return await operation();
    } finally {
      try {
        await _waitForForeground(epoch);
      } finally {
        _devicePromptActive = false;
      }
    }
  }

  Future<void> _waitForForeground(int epoch) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      if (!mounted || epoch != _viewEpoch) throw PreviewLocked();
      final state = WidgetsBinding.instance.lifecycleState;
      if (state == null || state == AppLifecycleState.resumed) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw PreviewLocked();
  }

  void _requireForeground(int epoch) {
    final state = WidgetsBinding.instance.lifecycleState;
    if (!mounted ||
        epoch != _viewEpoch ||
        (state != null && state != AppLifecycleState.resumed)) {
      throw PreviewLocked();
    }
  }

  void _clear() {
    _clearSimpleImport();
    _clearSimpleExport();
    for (final c in [
      _password,
      _pin,
      _pinConfirm,
      _confirm,
      _name,
      _amount,
      _cardClosingDay,
      _cardDueDay,
      _cardLimit,
      _fee,
      _received,
      _reversalReason,
      _correctionReason,
      _noteText,
      _date,
      _credential,
    ]) {
      c.clear();
    }
    _resetSplits();
    _refund = null;
    _reversal = null;
    _correction = null;
    _noteTarget = null;
    _noteRevision = 0;
    _noteText.clear();
    _reversalReason.clear();
    _correctionReason.clear();
    _draft = null;
    _saved = false;
    _accounts = [];
    _entries = [];
    _deletedEntries = [];
    _monthlyReport = null;
    _monthlyOverflow = false;
    _recurringReminderRequest++;
    _recurringDueCount = null;
    _recurringReminderError = false;
    _assetReport = null;
    _assetOverflow = false;
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
    _pendingCardTerms = null;
    _inputSignature = null;
    _entryDraft = null;
    _draftUnreadable = false;
    _draftSaveError = null;
    _privacy = PrivacyMode.hidden;
    _rememberDevice = false;
  }

  void _lock() {
    final engine = _engine;
    if (engine == null) return;
    _viewEpoch++;
    _lockBarrier = _draftSaveTail.then((_) => engine.lock());
    unawaited(
      _lockBarrier!.catchError((Object _) {
        if (mounted) {
          setState(() {
            _page = _Page.blocked;
            _message = '資料庫關閉未能完成，已停止操作。請保留現有資料。';
          });
        }
      }),
    );
    if (!mounted) return;
    widget.onLock();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _clear();
      _page = _Page.locked;
      _message = null;
    });
    unawaited(_resolveLockedPage());
  }

  Future<void> _resolveLockedPage() async {
    if (_busy) return;
    try {
      final exists = await _engine!.hasProfile();
      if (mounted && !_engine!.isUnlocked && !_busy) {
        setState(() {
          _page = exists ? _Page.locked : _Page.setup;
        });
      }
    } catch (_) {
      if (mounted && !_busy && !_engine!.isUnlocked) {
        final safety = await _availableLockedSafetyCopy(_engine!);
        final upgradeSafety = await _availableLockedUpgradeCopy(_engine!);
        if (mounted && !_busy && !_engine!.isUnlocked) {
          setState(() {
            _hasSafety = safety;
            _hasUpgradeSafety = upgradeSafety;
            _page = _Page.blocked;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // The view is being disposed; the engine retains a failed close future and
    // refuses subsequent sessions. There is no remaining view to notify here.
    _viewEpoch++;
    unawaited(
      _draftSaveTail.then((_) => _engine?.lock()).catchError((Object _) {}),
    );
    for (final c in [
      _password,
      _pin,
      _pinConfirm,
      _confirm,
      _name,
      _amount,
      _fee,
      _received,
      _reversalReason,
      _correctionReason,
      _noteText,
      _date,
      _credential,
    ]) {
      c.dispose();
    }
    for (final row in _splitRows) {
      row.amount.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final epoch = _viewEpoch;
    try {
      await _lockBarrier;
      await _draftSaveTail;
      if (!mounted || epoch != _viewEpoch) return;
      await action();
    } catch (error) {
      if (mounted && epoch == _viewEpoch) {
        if (error is PreviewDataUnavailable) {
          final safety = await _availableLockedSafetyCopy(_engine!);
          final upgradeSafety = await _availableLockedUpgradeCopy(_engine!);
          if (!mounted || epoch != _viewEpoch) return;
          setState(() {
            _hasSafety = safety;
            _hasUpgradeSafety = upgradeSafety;
            _page = _Page.blocked;
            _message = _error(error);
          });
        } else {
          setState(() => _message = _error(error));
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              epoch == _viewEpoch &&
              _message != null &&
              _scroll.hasClients) {
            _scroll.jumpTo(0);
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_page == _Page.locked) await _resolveLockedPage();
      }
    }
  }

  Future<void> _loadRecurringReminder() async {
    final request = ++_recurringReminderRequest;
    final epoch = _viewEpoch;
    try {
      final now = DateTime.now();
      final start = DateTime(now.year - 1, now.month, now.day);
      final due = await _engine!.dueRecurringCandidates(
        after: BusinessDate(start.year, start.month, start.day),
        through: BusinessDate(now.year, now.month, now.day),
      );
      if (!mounted ||
          epoch != _viewEpoch ||
          request != _recurringReminderRequest ||
          !_engine!.isUnlocked ||
          _page != _Page.home) {
        return;
      }
      setState(() {
        _recurringDueCount = due.length;
        _recurringReminderError = false;
      });
    } catch (_) {
      if (!mounted ||
          epoch != _viewEpoch ||
          request != _recurringReminderRequest ||
          !_engine!.isUnlocked ||
          _page != _Page.home) {
        return;
      }
      setState(() {
        _recurringDueCount = null;
        _recurringReminderError = true;
      });
    }
  }

  Future<void> _refresh() async {
    final privacy = await _engine!.privacyMode();
    final accounts = await _engine!.accounts();
    AssetReport? assetReport;
    var assetOverflow = false;
    try {
      assetReport = AssetReport.build([
        for (final row in accounts)
          if (row.account.kind != AccountKind.creditCard)
            AssetBalanceFact(
              row.account.id,
              row.balance,
              row.account.includeInNetWorth,
            ),
      ]);
    } on MoneyException {
      assetOverflow = true;
    }
    final entries = await _engine!.entries();
    final deletedEntries = _engine!.capabilities.tombstones
        ? await _engine!.deletedEntries()
        : const <LedgerEntry>[];
    final catalog = await _engine!.categories();
    final labels = await _categoryLabels(entries, catalog);
    final tagCatalog = _engine!.capabilities.tags
        ? await _engine!.tags()
        : null;
    final tagLabels = await _tagLabels(entries, tagCatalog);
    final merchantCatalog = _engine!.capabilities.merchants
        ? await _engine!.merchants()
        : null;
    final merchantLabels = await _merchantLabels(entries, merchantCatalog);
    final now = DateTime.now();
    MonthlyReport? monthlyReport;
    var monthlyOverflow = false;
    try {
      monthlyReport = await _engine!.monthlyReport(
        ReportMonth(now.year, now.month),
      );
    } on MoneyException {
      monthlyOverflow = true;
    }
    final safety = await _engine!.hasSafetyCopy();
    final upgradeSafety = await _engine!.hasLockedUpgradeCopy();
    EntryDraft? entryDraft;
    var draftUnreadable = false;
    try {
      entryDraft = await _engine!.entryDraft();
    } on DraftUnavailable {
      draftUnreadable = true;
    }
    if (!mounted || !_engine!.isUnlocked) return;
    setState(() {
      _privacy = _forceHidden ? PrivacyMode.hidden : privacy;
      _accounts = accounts;
      _entries = entries;
      _deletedEntries = deletedEntries;
      _monthlyReport = monthlyReport;
      _monthlyOverflow = monthlyOverflow;
      _recurringDueCount = null;
      _recurringReminderError = false;
      _assetReport = assetReport;
      _assetOverflow = assetOverflow;
      _entryDraft = entryDraft;
      _draftUnreadable = draftUnreadable;
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
      _hasMoreDeleted = deletedEntries.length == 30;
      _hasSafety = safety;
      _hasUpgradeSafety = upgradeSafety;
      _page = _simpleImportSelected
          ? _Page.simpleImport
          : _simpleExportSelected
          ? _Page.simpleExport
          : _imported == null
          ? _Page.home
          : _Page.restore;
    });
    if (_engine!.capabilities.recurring && _page == _Page.home) {
      unawaited(_loadRecurringReminder());
    }
  }

  Future<void> _unlock({bool upgrade = false}) => _perform(() async {
    final password = _password.text;
    try {
      if (upgrade) {
        await _engine!.upgrade(password);
      } else {
        await _engine!.unlock(password);
      }
    } on PreviewUpgradeRequired {
      if (mounted) setState(() => _page = _Page.upgrade);
      return;
    }
    _password.clear();
    var deviceError = false;
    if (_rememberDevice && widget.deviceUnlock != null) {
      // Do not leave any financial content behind the system prompt.
      if (mounted) setState(() => _page = _Page.locked);
      try {
        // A disabled shortcut must never revive a verifier from a prior setup.
        await widget.appPin?.disable();
        await _withDevicePrompt(() => widget.deviceUnlock!.enable(password));
        _deviceUnlockEnabled = true;
        _pinEnabled = false;
      } catch (_) {
        deviceError = true;
      }
    }
    await _refresh();
    if (mounted && deviceError) {
      setState(() => _message = '裝置解鎖未啟用；仍可使用帳本密碼。');
    }
  });

  Future<void> _unlockWithDevice() => _perform(() async {
    if (_pinEnabled || (await widget.appPin?.isEnabled() ?? false)) {
      throw PreviewInvalid();
    }
    final password = await _withDevicePrompt(
      () => widget.deviceUnlock!.readPassword(),
    );
    if (password == null) throw PreviewInvalid();
    try {
      await _engine!.unlock(password);
    } on PreviewUpgradeRequired {
      if (mounted) setState(() => _page = _Page.upgrade);
      return;
    }
    await _refresh();
  });

  Future<void> _unlockWithPin() => _perform(() async {
    if (!_pinEnabled || !_deviceUnlockEnabled || widget.appPin == null) {
      throw PreviewInvalid();
    }
    final pin = _pin.text;
    final epoch = _viewEpoch;
    try {
      // The Keystore prompt is required on every attempt; a short PIN alone
      // never unwraps the ledger password or becomes an offline backup key.
      final password = await _withDevicePrompt(
        () => widget.deviceUnlock!.readPassword(),
      );
      if (password == null || !await widget.appPin!.matches(pin)) {
        throw const AppPinRejected();
      }
      _requireForeground(epoch);
      try {
        await _engine!.unlock(password);
      } on PreviewUpgradeRequired {
        if (mounted) setState(() => _page = _Page.upgrade);
        return;
      }
      await _refresh();
    } finally {
      _pin.clear();
    }
  });

  Future<void> _enableAppPin() => _perform(() async {
    try {
      if (!_engine!.isUnlocked ||
          !_deviceUnlockEnabled ||
          _pinEnabled ||
          widget.appPin == null) {
        throw PreviewInvalid();
      }
      if (_pin.text != _pinConfirm.text) {
        throw const FormatException('App PIN confirmation');
      }
      if (!RegExp(r'^[0-9]{6,12}$').hasMatch(_pin.text)) {
        throw const FormatException('App PIN format');
      }
      final pin = _pin.text;
      final epoch = _viewEpoch;
      final password = await _withDevicePrompt(
        () => widget.deviceUnlock!.readPassword(),
      );
      if (password == null) throw PreviewInvalid();
      await widget.appPin!.enable(pin);
      if (epoch != _viewEpoch) {
        await widget.appPin!.disable();
        throw PreviewLocked();
      }
      _requireForeground(epoch);
      _pinEnabled = true;
      await _refresh();
    } finally {
      _pin.clear();
      _pinConfirm.clear();
    }
  });

  Future<void> _disableAppPin() => _perform(() async {
    if (!_engine!.isUnlocked || !_pinEnabled || widget.appPin == null) {
      throw PreviewInvalid();
    }
    final pin = _pin.text;
    final epoch = _viewEpoch;
    try {
      final password = await _withDevicePrompt(
        () => widget.deviceUnlock!.readPassword(),
      );
      if (password == null || !await widget.appPin!.matches(pin)) {
        throw const AppPinRejected();
      }
      _requireForeground(epoch);
      await widget.appPin!.disable();
      _pinEnabled = false;
      await _refresh();
    } finally {
      _pin.clear();
    }
  });

  Future<void> _disableDeviceUnlock() => _perform(() async {
    if (mounted) setState(() => _page = _Page.locked);
    try {
      await _withDevicePrompt(() => widget.deviceUnlock!.disable());
      await widget.appPin?.disable();
      _pinEnabled = false;
    } finally {
      final enabled = await widget.deviceUnlock!.isEnabled();
      if (mounted) setState(() => _deviceUnlockEnabled = enabled);
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (_engine!.isUnlocked &&
          (lifecycle == null || lifecycle == AppLifecycleState.resumed)) {
        await _refresh();
      }
    }
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
  void _edit(_Page page, {bool transfer = false}) {
    setState(() {
      _resetSplits();
      _refund = null;
      _reversal = null;
      _correction = null;
      _noteTarget = null;
      _noteRevision = 0;
      _noteText.clear();
      _reversalReason.clear();
      _correctionReason.clear();
      _page = page;
      _transfer = transfer || page == _Page.cardPayment;
      if (_transfer) _income = false;
      _destinationId = null;
      _fee.text = '0';
      _received.clear();
      _message = null;
      _name.clear();
      _amount.text = page == _Page.account ? '0' : '';
      final now = DateTime.now();
      _date.text = BusinessDate(now.year, now.month, now.day).toString();
      _pendingPosting = null;
      _pendingAccount = null;
      _pendingCardTerms = null;
      _inputSignature = null;
      _categoryId = '';
      _merchantId = '';
      _selectedTags.clear();
      _accountId = _accounts
          .where(
            (a) =>
                a.account.state == AccountState.active &&
                (page == _Page.cardPurchase
                    ? a.account.kind == AccountKind.creditCard
                    : page == _Page.cardPayment
                    ? a.account.kind == AccountKind.bank &&
                          _accounts.any(
                            (card) =>
                                card.account.state == AccountState.active &&
                                card.account.kind == AccountKind.creditCard &&
                                card.balance.minorUnits < BigInt.zero &&
                                card.account.currency == a.account.currency,
                          )
                    : a.account.kind != AccountKind.creditCard),
          )
          .firstOrNull
          ?.account
          .id;
      if (page == _Page.cardPayment) {
        _destinationId = _cardPaymentDestinations.firstOrNull?.account.id;
      }
    });
  }

  Currency? get _sourceCurrency => _accounts
      .where((a) => a.account.id == _accountId)
      .firstOrNull
      ?.account
      .currency;
  Iterable<AccountSummary> get _destinations => _accounts.where(
    (a) =>
        a.account.state == AccountState.active &&
        a.account.kind != AccountKind.creditCard &&
        a.account.id != _accountId &&
        (a.account.currency == _sourceCurrency ||
            (_engine!.capabilities.crossCurrencyTransfers &&
                a.account.currency.code != _sourceCurrency?.code)),
  );
  Iterable<AccountSummary> get _cardPaymentDestinations => _accounts.where(
    (a) =>
        a.account.kind == AccountKind.creditCard &&
        ((a.account.state == AccountState.active &&
                a.balance.minorUnits < BigInt.zero &&
                a.account.currency == _sourceCurrency) ||
            a.account.id == _destinationId),
  );
  Currency? get _destinationCurrency => _accounts
      .where((a) => a.account.id == _destinationId)
      .firstOrNull
      ?.account
      .currency;
  bool get _foreignTransfer =>
      _transfer &&
      _sourceCurrency != null &&
      _destinationCurrency != null &&
      _sourceCurrency != _destinationCurrency;
  String _accountName(PublicId? id) =>
      _accounts.where((a) => a.account.id == id).firstOrNull?.account.name ??
      '帳戶';

  Future<void> _copyPosting(PublicId id) => _perform(() async {
    await _refresh();
    if (_entryDraft != null || _draftUnreadable) throw DraftNeedsResolution();
    final copy = await _engine!.preparePostingCopy(id);
    if (!mounted || !_engine!.isUnlocked) return;
    _edit(_Page.posting);
    setState(() {
      _income = copy.income;
      _accountId = copy.account.id;
      _categoryId = copy.categoryId?.value ?? '';
      if (copy.splitCategories.isNotEmpty) {
        _split = true;
        _splitRows.addAll(copy.splitCategories.map((id) => _SplitRow(id, '')));
      }
      _merchantId = copy.merchant?.id.value ?? '';
      _selectedTags.addAll(copy.tags.map((tag) => tag.id));
      _date.clear();
      _message = copy.omittedMetadata
          ? '已沿用可用欄位；部分分類、標籤或商家需重新選擇。請輸入本次金額與日期。'
          : '已沿用帳戶、分類、標籤與商家；請輸入本次金額與日期。';
    });
  });

  void _changeNote(VoidCallback change) => setState(change);

  void _changeSplit(VoidCallback change) => setState(change);

  void _queueDraft() {
    if ((_page != _Page.posting &&
            _page != _Page.cardPurchase &&
            _page != _Page.cardPayment) ||
        _postingFrozen) {
      return;
    }
    final epoch = _viewEpoch;
    final engine = _engine!;
    final fields = _noteTarget != null
        ? EntryFields(
            income: false,
            amount: '',
            date: '',
            noteOf: _noteTarget,
            noteRevision: _noteRevision,
            noteText: _noteText.text,
          )
        : _reversal != null
        ? EntryFields(
            income: false,
            amount: '',
            date: _date.text,
            reversalOf: _reversal!.posting.id,
            reversalReason: _reversalReason.text,
          )
        : EntryFields(
            income: (_page == _Page.cardPurchase || _page == _Page.cardPayment)
                ? false
                : _income,
            correctionOf: _correction?.posting.id,
            correctionReason: _correction == null ? '' : _correctionReason.text,
            refundOf: _refund?.budget.originalId,
            split: _split,
            splits: [
              for (final row in _splitRows)
                SplitFields(categoryId: row.category, amount: row.amount.text),
            ],
            transfer: _transfer,
            destinationId: _destinationId,
            fee: _page == _Page.cardPayment
                ? '0'
                : _transfer
                ? _fee.text
                : '0',
            received: (_foreignTransfer || _foreignRefund)
                ? _received.text
                : null,
            amount: _amount.text,
            date: _date.text,
            accountId: _accountId,
            categoryId: _categoryId.isEmpty
                ? null
                : PublicId.parse(_categoryId),
            merchantId: _merchantId.isEmpty
                ? null
                : PublicId.parse(_merchantId),
            tags: _selectedTags,
          );
    setState(() => _draftWrites++);
    _draftSaveTail = _draftSaveTail.then((_) async {
      try {
        final draft = await engine.saveEntryDraft(fields);
        if (mounted && epoch == _viewEpoch) {
          setState(() {
            _entryDraft = draft;
            _draftSaveError = null;
          });
        }
      } catch (error) {
        if (mounted && epoch == _viewEpoch) {
          setState(() => _draftSaveError = error);
        }
      } finally {
        _draftWrites--;
        if (mounted && epoch == _viewEpoch) setState(() {});
      }
    });
  }

  Future<void> _resumeDraft() => _perform(() async {
    final saved = await _engine!.entryDraft();
    if (saved == null) {
      await _refresh();
      return;
    }
    final fields = saved.fields;
    if (fields.tombstoneOf != null) {
      await _resumeTombstone(saved);
      return;
    }
    if (fields.noteOf != null) {
      _resumeNote(saved);
      return;
    }
    if (fields.reversalOf != null) {
      await _resumeReversal(saved);
      return;
    }
    if (fields.refundOf != null) {
      await _resumeRefund(saved);
      return;
    }
    final correctionSource = fields.correctionOf == null
        ? null
        : saved.correctionSubmission == null
        ? await _engine!.reversalSource(fields.correctionOf!)
        : EntrySubmission(saved.correctionSubmission!.pair.original);
    final cardDraft =
        fields.accountId != null &&
        _accounts.any(
          (a) =>
              a.account.id == fields.accountId &&
              a.account.kind == AccountKind.creditCard,
        );
    final cardPaymentDraft =
        fields.transfer &&
        fields.destinationId != null &&
        _accounts.any(
          (a) =>
              a.account.id == fields.destinationId &&
              a.account.kind == AccountKind.creditCard,
        );
    _edit(
      cardDraft
          ? _Page.cardPurchase
          : cardPaymentDraft
          ? _Page.cardPayment
          : _Page.posting,
      transfer: fields.transfer,
    );
    var omitted = false;
    setState(() {
      _entryDraft = saved;
      _correction = correctionSource;
      _correctionReason.text = fields.correctionReason;
      _draftSaveError = null;
      _income = fields.income;
      _fee.text = fields.fee;
      _received.text = fields.received ?? '';
      _amount.text = fields.amount;
      _date.text = fields.date;
      _accountId =
          _accounts.any(
            (a) =>
                a.account.id == fields.accountId &&
                a.account.state == AccountState.active &&
                (cardDraft
                    ? a.account.kind == AccountKind.creditCard
                    : cardPaymentDraft
                    ? a.account.kind == AccountKind.bank
                    : a.account.kind != AccountKind.creditCard),
          )
          ? fields.accountId
          : null;
      if (fields.accountId != null && _accountId == null) omitted = true;
      _destinationId =
          (cardPaymentDraft
              ? _accounts.any(
                  (a) =>
                      a.account.id == fields.destinationId &&
                      a.account.kind == AccountKind.creditCard,
                )
              : _destinations.any((a) => a.account.id == fields.destinationId))
          ? fields.destinationId
          : null;
      if (fields.destinationId != null && _destinationId == null) {
        omitted = true;
      }
      final categories = _catalog!.categories.where(
        (c) =>
            c.id == fields.categoryId &&
            !c.archived &&
            c.replacementId == null &&
            c.kind == (_income ? CategoryKind.income : CategoryKind.expense),
      );
      _categoryId = categories.firstOrNull?.id.value ?? '';
      if (fields.categoryId != null && _categoryId.isEmpty) omitted = true;
      if (fields.split) {
        _split = true;
        for (final row in fields.splits) {
          final available = _catalog!.categories.any(
            (c) =>
                c.id == row.categoryId &&
                !_splitRows.any((used) => used.category == c.id) &&
                !c.archived &&
                c.replacementId == null &&
                c.kind ==
                    (_income ? CategoryKind.income : CategoryKind.expense),
          );
          if (row.categoryId != null && !available) omitted = true;
          _splitRows.add(
            _SplitRow(available ? row.categoryId : null, row.amount),
          );
        }
      }
      _selectedTags.clear();
      for (final id in fields.tags) {
        if (_tagCatalog?.tags.any(
              (t) => t.id == id && !t.archived && t.replacementId == null,
            ) ??
            false) {
          _selectedTags.add(id);
        } else {
          omitted = true;
        }
      }
      final merchants = _merchantCatalog?.merchants.where(
        (m) =>
            m.id == fields.merchantId && !m.archived && m.replacementId == null,
      );
      _merchantId = merchants?.firstOrNull?.id.value ?? '';
      if (fields.merchantId != null && _merchantId.isEmpty) omitted = true;
      _message = omitted
          ? '部分帳戶或分類資料已停用，請重新選擇並確認。原草稿仍保留。'
          : fields.correctionOf != null
          ? '已恢復更正草稿，請確認原交易及替代金額後送出。'
          : '已恢復草稿，請確認欄位後再儲存收支。';
    });
  });

  Future<void> _discardDraft() => _perform(() async {
    final epoch = _viewEpoch;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('捨棄本機草稿？'),
        content: const Text('未完成的欄位將移除；已入帳的交易不會刪除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('保留'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確認捨棄'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        epoch != _viewEpoch ||
        !_engine!.isUnlocked) {
      return;
    }
    await _engine!.discardEntryDraft();
    await _refresh();
  });

  PostingAccount _ref(Account a) => PostingAccount(
    id: a.id,
    workspace: a.workspace,
    currency: a.currency,
    expectedVersion: a.version,
  );
  Future<void> _saveAccount() => _perform(() async {
    final signature =
        '$_kind|$_currency|${_name.text}|${_amount.text}|${_date.text}|'
        '${_cardClosingDay.text}|${_cardDueDay.text}|${_cardLimit.text}';
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
        amount: _kind == AccountKind.creditCard
            ? Money(a.currency, BigInt.zero)
            : Money.parse(a.currency, _amount.text),
      );
      _pendingAccount = a;
      _pendingPosting = p;
      _pendingCardTerms = _kind == AccountKind.creditCard
          ? CreditCardTerms(
              workspace: a.workspace,
              cardId: a.id,
              currency: a.currency,
              closingDay: int.parse(_cardClosingDay.text),
              dueDay: int.parse(_cardDueDay.text),
              limit: _cardLimit.text.trim().isEmpty
                  ? null
                  : Money.parse(a.currency, _cardLimit.text),
            )
          : null;
      _inputSignature = signature;
    }
    await _engine!.createAccount(
      _pendingAccount!,
      _pendingPosting!,
      cardTerms: _pendingCardTerms,
    );
    await _refresh();
  });
  Future<void> _savePosting() => _perform(() async {
    if (_reversal != null && !_postingFrozen && !await _confirmReversal()) {
      return;
    }
    if (_correction != null && !_postingFrozen && !await _confirmCorrection()) {
      return;
    }
    if (!_postingFrozen) {
      _queueDraft();
      await _draftSaveTail;
      if (_draftSaveError != null) throw _draftSaveError!;
    }
    try {
      await _engine!.submitEntryDraft();
    } catch (_) {
      if (_engine!.isUnlocked) {
        final saved = await _engine!.entryDraft();
        if (mounted) setState(() => _entryDraft = saved);
        if (saved == null) {
          await _refresh();
          return;
        }
      }
      rethrow;
    }
    await _refresh();
  });
  Future<void> _togglePrivacy() => _perform(() async {
    final epoch = _viewEpoch;
    final next = _privacy == PrivacyMode.visible
        ? PrivacyMode.hidden
        : PrivacyMode.visible;
    if (next == PrivacyMode.hidden) {
      setState(() {
        _privacy = next;
        _forceHidden = true;
      });
    }
    try {
      await _engine!.setPrivacyMode(next);
      if (mounted && epoch == _viewEpoch && _engine!.isUnlocked) {
        setState(() {
          _privacy = next;
          _forceHidden = false;
        });
      }
    } catch (_) {
      if (mounted && epoch == _viewEpoch && _engine!.isUnlocked) {
        setState(() {
          _privacy = PrivacyMode.hidden;
          _forceHidden = true;
          _message = '遮罩設定尚未保存，本次開啟期間維持隱藏。請稍後重試。';
        });
      }
    }
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
  Future<void> _exportLockedSafetyCopy() => _perform(() async {
    final encrypted = await _engine!.exportLockedSafetyCopy(
      _credential.text,
      recovery: _useRecovery,
    );
    final saved = await widget.documents.save(encrypted);
    _credential.clear();
    if (mounted) {
      setState(
        () => _message = saved
            ? '加密安全副本已儲存；可於新的 V2 安裝中用原密碼或救援文字還原。'
            : '已取消儲存；本機帳本未變更。',
      );
    }
  });

  Future<void> _exportLockedUpgradeCopy() => _perform(() async {
    final encrypted = await _engine!.exportLockedUpgradeCopy(
      _credential.text,
      recovery: _useRecovery,
    );
    final saved = await widget.documents.save(encrypted);
    _credential.clear();
    if (mounted) {
      setState(
        () => _message = saved
            ? '升級前加密備份已儲存；可能是較早版本，可用原憑證還原後依提示更新。'
            : '已取消儲存；本機帳本未變更。',
      );
    }
  });

  List<Widget> _lockedSafetyControls() => [
    const SizedBox(height: 16),
    const Text('帳本無法開啟時，可用原密碼或救援文字驗證並匯出加密安全副本。此操作不會替換目前資料。'),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('使用救援文字'),
      value: _useRecovery,
      onChanged: _busy
          ? null
          : (value) => setState(() {
              _useRecovery = value;
              _credential.clear();
            }),
    ),
    _field(_useRecovery ? '原帳本救援文字' : '原帳本密碼', _credential, secret: true),
    if (_hasSafety) _button('匯出還原前加密安全副本', _exportLockedSafetyCopy),
    if (_hasUpgradeSafety) ...[
      const Text('升級副本可能是較早版本；優先匯出最近一份可驗證的檔案。'),
      _button('匯出升級前加密備份', _exportLockedUpgradeCopy),
    ],
  ];

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
  Future<void> _moreDeleted() => _perform(() async {
    final next = await _engine!.deletedEntries(before: _deletedEntries.last);
    if (mounted && _engine!.isUnlocked) {
      setState(() {
        _deletedEntries.addAll(next);
        _hasMoreDeleted = next.length == 30;
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
      if (entry.kind == PostingKind.transfer) continue;
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
      if (entry.kind == PostingKind.transfer) continue;
      final refs = await _engine!.tagsFor(entry.id);
      if (refs.isNotEmpty) {
        result[entry.id] = refs
            .map((r) => '#${_tagLabel(catalog, catalog.get(r.id))}')
            .join('、');
      }
    }
    return result;
  }

  Future<Map<PublicId, List<LedgerAllocation>>> _categoryLabels(
    List<LedgerEntry> entries,
    CategoryCatalog catalog,
  ) async {
    final result = <PublicId, List<LedgerAllocation>>{};
    for (final entry in entries) {
      if (entry.kind == PostingKind.opening ||
          entry.kind == PostingKind.transfer) {
        continue;
      }
      result[entry.id] = await _engine!.allocations(entry.id);
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
      enabled: !_busy && !_postingFrozen,
      onChanged: (_) {
        if (_page == _Page.posting ||
            _page == _Page.cardPurchase ||
            _page == _Page.cardPayment) {
          _queueDraft();
        }
      },
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: !secret,
      keyboardType: controller == _pin || controller == _pinConfirm
          ? TextInputType.number
          : null,
      inputFormatters: controller == _pin || controller == _pinConfirm
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      maxLength: length ?? (_page == _Page.posting ? 128 : null),
      decoration: InputDecoration(labelText: label),
      onSubmitted: secret && _page == _Page.locked
          ? (_) => controller == _pin ? _unlockWithPin() : _unlock()
          : null,
    ),
  );
  Widget _dateField({bool opening = false}) {
    final epoch = _viewEpoch;
    final page = _page;
    final strings = AppLocalizations.of(context);
    return BusinessDateInputField(
      controller: _date,
      label: opening ? strings.openingDateLabel : strings.entryDateLabel,
      help: opening ? strings.openingDateHelp : strings.dateHelp,
      enabled: !_busy && !_postingFrozen,
      canApply: () =>
          mounted &&
          epoch == _viewEpoch &&
          page == _page &&
          !_busy &&
          !_postingFrozen &&
          _engine!.isUnlocked,
      onChanged: () {
        if (_page == _Page.posting ||
            _page == _Page.cardPurchase ||
            _page == _Page.cardPayment) {
          _queueDraft();
        }
      },
    );
  }

  Widget _amountField(String label, Currency? currency) => AmountInputField(
    controller: _amount,
    label: label,
    currency: currency,
    enabled: !_busy && !_postingFrozen,
    onChanged: () {
      if (_page == _Page.posting ||
          _page == _Page.cardPurchase ||
          _page == _Page.cardPayment) {
        _queueDraft();
      }
    },
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
        : () => _perform(() async {
            if (_draftSaveError != null &&
                (_page == _Page.posting ||
                    _page == _Page.cardPurchase ||
                    _page == _Page.cardPayment)) {
              _queueDraft();
              await _draftSaveTail;
              if (_draftSaveError != null) throw _draftSaveError!;
            }
            _imported = null;
            if (_page == _Page.simpleImport) {
              _clearSimpleImport();
              await widget.documents.discardSimpleImport();
            }
            if (_page == _Page.simpleExport) {
              _clearSimpleExport();
              await widget.documents.discardSimpleExport();
            }
            _credential.clear();
            _pin.clear();
            _pinConfirm.clear();
            await _refresh();
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
        if ({
              _Page.home,
              _Page.search,
              _Page.monthlyReport,
              _Page.budgets,
              _Page.recurring,
              _Page.cardStatements,
              _Page.simpleImport,
              _Page.simpleExport,
            }.contains(_page) &&
            (_engine?.isUnlocked ?? false))
          IconButton(
            onPressed: _busy ? null : _togglePrivacy,
            tooltip: _privacy == PrivacyMode.hidden ? '顯示金額' : '隱藏金額',
            icon: Icon(
              _privacy == PrivacyMode.hidden
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
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
            key: ValueKey(_page),
            controller: _scroll,
            padding: const EdgeInsets.all(20),
            children: [
              const Text('開發驗證版', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(_message!, key: const Key('message')),
                  ),
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
      case _Page.search:
        return [
          _SearchScreen(
            engine: _engine!,
            accounts: _accounts,
            categories: _catalog!.categories,
            tags: _tagCatalog?.tags ?? const [],
            merchants: _merchantCatalog?.merchants ?? const [],
            privacy: _privacy,
            onActivity: _showActivity,
          ),
          _back(),
        ];
      case _Page.monthlyReport:
        return [
          _MonthlyReportScreen(
            engine: _engine!,
            initial: _monthlyReport!,
            catalog: _catalog!,
            accounts: _accounts,
            merchants: _merchantCatalog,
            privacy: _privacy,
            onActivity: _showActivity,
          ),
          _back(),
        ];
      case _Page.budgets:
        return [
          _BudgetScreen(
            engine: _engine!,
            catalog: _catalog!,
            tags: _tagCatalog,
            accounts: _accounts,
            privacy: _privacy,
          ),
          _back(),
        ];
      case _Page.recurring:
        return [
          _RecurringScreen(
            engine: _engine!,
            accounts: _accounts,
            privacy: _privacy,
            reminder: widget.recurringReminder,
          ),
          _back(),
        ];
      case _Page.cardStatements:
        return [
          _CardStatementScreen(
            engine: _engine!,
            accounts: _accounts,
            privacy: _privacy,
          ),
          _back(),
        ];
      case _Page.loading:
        return [const Center(child: CircularProgressIndicator())];
      case _Page.blocked:
        return [
          const Text('設定或儲存發生問題，已停止開啟帳本。請保留現有資料與加密備份。'),
          if (_engine != null && (_hasSafety || _hasUpgradeSafety))
            ..._lockedSafetyControls(),
        ];
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
      case _Page.pinSetup:
        return [
          Text('設定 App PIN', style: Theme.of(context).textTheme.headlineSmall),
          const Text('App PIN 需搭配每次裝置認證；帳本密碼與救援文字維持獨立。'),
          _field('新 App PIN（6–12 位數字）', _pin, secret: true, length: 12),
          _field('再次輸入 App PIN', _pinConfirm, secret: true, length: 12),
          _button('啟用 App PIN', _enableAppPin),
          _back(),
        ];
      case _Page.pinDisable:
        return [
          Text('停用 App PIN', style: Theme.of(context).textTheme.headlineSmall),
          const Text('需輸入目前 App PIN 並通過裝置認證。忘記 PIN 時可用帳本密碼解鎖，再停用本機裝置解鎖。'),
          _field('目前 App PIN', _pin, secret: true, length: 12),
          _button('確認停用 App PIN', _disableAppPin),
          _back(),
        ];
      case _Page.locked:
        return [
          Text('解鎖帳本', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),
          _field('密碼', _password, secret: true),
          _button('解鎖', _unlock),
          if (widget.deviceUnlock != null && !_deviceUnlockEnabled)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('在這台手機啟用裝置解鎖'),
              subtitle: const Text('需先用帳本密碼解鎖，並通過手機的生物辨識或螢幕鎖；加密備份仍須原密碼或救援文字。'),
              value: _rememberDevice,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _rememberDevice = value ?? false),
            ),
          if (widget.deviceUnlock != null &&
              _deviceUnlockEnabled &&
              !_pinEnabled)
            _button('使用裝置解鎖', _unlockWithDevice),
          if (widget.deviceUnlock != null &&
              _deviceUnlockEnabled &&
              _pinEnabled) ...[
            _field('App PIN（6–12 位數字）', _pin, secret: true, length: 12),
            _button('使用 App PIN 與裝置認證', _unlockWithPin),
          ],
          if (_hasSafety || _hasUpgradeSafety) ..._lockedSafetyControls(),
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
              DropdownMenuItem(
                value: AccountKind.creditCard,
                child: Text('信用卡'),
              ),
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
          if (_kind == AccountKind.creditCard) ...[
            const Text('目前可建立卡片與保存帳期；刷卡、繳款及帳單仍在開發，暫不開放記錄。'),
            _field('結帳日（1–31）', _cardClosingDay, length: 2),
            _field('繳款日（1–31）', _cardDueDay, length: 2),
            _field('額度（可留空）', _cardLimit, length: 24),
          ] else
            _amountField(
              '期初餘額',
              Currency(_currency, _currency == 'JPY' ? 0 : 2),
            ),
          _dateField(opening: true),
          _button('建立帳戶', _saveAccount),
          _back(),
        ];
      case _Page.cardPurchase:
        return [
          Text('信用卡刷卡入帳', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          const Text('只記錄已正式入帳的本幣刷卡。待入帳授權、外幣與額外手續費尚未開放。'),
          const SizedBox(height: 16),
          DropdownButtonFormField<PublicId>(
            key: const ValueKey('card-purchase-account'),
            initialValue: _accountId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '信用卡'),
            items: [
              for (final row in _accounts.where(
                (row) =>
                    row.account.state == AccountState.active &&
                    row.account.kind == AccountKind.creditCard,
              ))
                DropdownMenuItem(
                  value: row.account.id,
                  child: Text(
                    '${row.account.name} · ${row.account.currency.code}',
                  ),
                ),
            ],
            onChanged: (_busy || _postingFrozen)
                ? null
                : (value) => setState(() {
                    _accountId = value;
                    _categoryId = '';
                    _queueDraft();
                  }),
          ),
          const SizedBox(height: 14),
          _amountField('實際入帳金額', _sourceCurrency),
          _dateField(),
          DropdownButtonFormField<String>(
            key: const ValueKey('card-purchase-category'),
            initialValue: _categoryId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '支出分類'),
            items: [
              const DropdownMenuItem(value: '', child: Text('未分類')),
              for (final category in _catalog!.categories.where(
                (category) =>
                    !category.archived &&
                    category.replacementId == null &&
                    category.kind == CategoryKind.expense,
              ))
                DropdownMenuItem(
                  value: category.id.value,
                  child: Text(
                    _categoryLabel(_catalog!, category),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (_busy || _postingFrozen)
                ? null
                : (value) => setState(() {
                    _categoryId = value ?? '';
                    _queueDraft();
                  }),
          ),
          const SizedBox(height: 14),
          Text(
            _draftSaveError != null
                ? '草稿保存失敗，請重試；尚未刷卡入帳。'
                : _draftWrites > 0
                ? '正在加密保存草稿…'
                : _postingFrozen
                ? '刷卡資料已固定；再次確認會安全重試同一筆。'
                : '草稿會先加密保存，確認後才入帳。',
            key: const ValueKey('card-purchase-draft-status'),
          ),
          _button('確認刷卡入帳', _savePosting),
          if (_entryDraft != null || _draftSaveError != null)
            TextButton(
              onPressed: _busy ? null : _discardDraft,
              child: const Text('捨棄刷卡草稿'),
            ),
          _back(),
        ];
      case _Page.cardPayment:
        return [
          Text('信用卡繳款', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          const Text('從同幣別銀行帳戶繳款；銀行餘額減少、卡片負債減少，不會再計為支出。目前尚未指派至特定帳單。'),
          const SizedBox(height: 16),
          DropdownButtonFormField<PublicId>(
            key: const ValueKey('card-payment-bank'),
            initialValue: _accountId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '付款銀行帳戶'),
            items: [
              for (final row in _accounts.where(
                (row) =>
                    row.account.state == AccountState.active &&
                    row.account.kind == AccountKind.bank &&
                    _accounts.any(
                      (card) =>
                          card.account.state == AccountState.active &&
                          card.account.kind == AccountKind.creditCard &&
                          card.balance.minorUnits < BigInt.zero &&
                          card.account.currency == row.account.currency,
                    ),
              ))
                DropdownMenuItem(
                  value: row.account.id,
                  child: Text(
                    '${row.account.name} · ${row.account.currency.code}',
                  ),
                ),
            ],
            onChanged: (_busy || _postingFrozen)
                ? null
                : (value) => setState(() {
                    _accountId = value;
                    _destinationId = null;
                    _destinationId =
                        _cardPaymentDestinations.firstOrNull?.account.id;
                    _queueDraft();
                  }),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<PublicId>(
            key: ValueKey('card-payment-card-$_accountId-$_destinationId'),
            initialValue: _destinationId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '繳款信用卡'),
            items: [
              for (final row in _cardPaymentDestinations)
                DropdownMenuItem(
                  value: row.account.id,
                  child: Text(
                    '${row.account.name} · ${row.account.currency.code}',
                  ),
                ),
            ],
            onChanged: (_busy || _postingFrozen)
                ? null
                : (value) => setState(() {
                    _destinationId = value;
                    _queueDraft();
                  }),
          ),
          const SizedBox(height: 14),
          _amountField('繳款金額', _sourceCurrency),
          _dateField(),
          const Text('繳款不得超過卡片目前未償負債；已儲存草稿可在重開後核對，不會重複扣款。'),
          const SizedBox(height: 14),
          Text(
            _draftSaveError != null
                ? '草稿保存失敗，請重試；尚未繳款。'
                : _draftWrites > 0
                ? '正在加密保存草稿…'
                : _postingFrozen
                ? '繳款資料已固定；再次確認只會核對同一筆。'
                : '草稿會先加密保存，確認後才扣款。',
            key: const ValueKey('card-payment-draft-status'),
          ),
          _button('確認信用卡繳款', _savePosting),
          if (_entryDraft != null || _draftSaveError != null)
            TextButton(
              onPressed: _busy ? null : _discardDraft,
              child: const Text('捨棄繳款草稿'),
            ),
          _back(),
        ];
      case _Page.posting:
        return [
          if (_noteTarget != null)
            ..._noteInputs()
          else if (_reversal != null)
            ..._reversalInputs()
          else if (_refund != null)
            ..._refundInputs()
          else ...[
            if (_correction != null) ..._correctionIntro(),
            Text(
              _correction != null
                  ? '替代交易'
                  : _transfer
                  ? '轉帳'
                  : '記一筆',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            if (_transfer)
              const Text('本金只移動帳戶餘額；手續費另外計入支出，從轉出帳戶扣除。')
            else if (_correction == null)
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('支出')),
                  ButtonSegment(value: true, label: Text('收入')),
                ],
                selected: {_income},
                onSelectionChanged: (_busy || _postingFrozen)
                    ? null
                    : (v) => setState(() {
                        _income = v.single;
                        _categoryId = '';
                        for (final row in _splitRows) {
                          row.category = null;
                        }
                        _merchantId = '';
                        _selectedTags.clear();
                        _queueDraft();
                      }),
              ),
            const SizedBox(height: 16),
            DropdownButtonFormField<PublicId>(
              initialValue: _accountId,
              decoration: InputDecoration(labelText: _transfer ? '轉出帳戶' : '帳戶'),
              isExpanded: true,
              items: [
                for (final s in _accounts.where(
                  (s) =>
                      s.account.state == AccountState.active &&
                      s.account.kind != AccountKind.creditCard,
                ))
                  DropdownMenuItem(
                    value: s.account.id,
                    child: Text(
                      '${s.account.name} · ${s.account.currency.code}',
                    ),
                  ),
              ],
              onChanged: (_busy || _postingFrozen)
                  ? null
                  : (v) => setState(() {
                      _accountId = v;
                      _received.clear();
                      if (!_destinations.any(
                        (a) => a.account.id == _destinationId,
                      )) {
                        _destinationId = null;
                      }
                      _queueDraft();
                    }),
            ),
            const SizedBox(height: 14),
            if (_transfer) ...[
              DropdownButtonFormField<PublicId>(
                key: ValueKey(
                  'transfer-destination-$_accountId-$_destinationId',
                ),
                initialValue: _destinationId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '轉入帳戶'),
                items: [
                  for (final a in _destinations)
                    DropdownMenuItem(
                      value: a.account.id,
                      child: Text(
                        _engine!.capabilities.crossCurrencyTransfers
                            ? '${a.account.name} · ${a.account.currency.code}'
                            : a.account.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (_busy || _postingFrozen)
                    ? null
                    : (value) => setState(() {
                        _destinationId = value;
                        _received.clear();
                        _queueDraft();
                      }),
              ),
              if (_destinations.isEmpty) const Text('請先建立另一個可轉入的帳戶。'),
              const SizedBox(height: 14),
            ],
            _amountField(
              _transfer && _engine!.capabilities.crossCurrencyTransfers
                  ? '轉出本金（正數）'
                  : '金額（正數）',
              _accounts
                  .where((a) => a.account.id == _accountId)
                  .firstOrNull
                  ?.account
                  .currency,
            ),
            if (_foreignTransfer) ...[
              AmountInputField(
                controller: _received,
                label: '實際轉入本金（正數）',
                currency: _destinationCurrency,
                enabled: !_busy && !_postingFrozen,
                onChanged: _queueDraft,
              ),
              const Text('填寫實際轉入金額；換算比例由兩邊本金計算，手續費另列於轉出幣別。'),
            ],
            if (_transfer)
              AmountInputField(
                controller: _fee,
                label: '手續費（可為 0）',
                currency: _sourceCurrency,
                enabled: !_busy && !_postingFrozen,
                onChanged: _queueDraft,
              ),
            _dateField(),
            if (!_transfer)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('拆分多個分類'),
                value: _split,
                onChanged: (_busy || _postingFrozen)
                    ? null
                    : (value) => setState(() {
                        if (value) {
                          _split = true;
                          _splitRows.addAll([
                            _SplitRow(
                              _categoryId.isEmpty
                                  ? null
                                  : PublicId.parse(_categoryId),
                              '',
                            ),
                            _SplitRow(null, ''),
                          ]);
                        } else {
                          _resetSplits();
                        }
                        _categoryId = '';
                        _queueDraft();
                      }),
              ),
            if (!_transfer && _split) ..._splitInputs(),
            if (!_transfer && !_split)
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
                            (_income
                                ? CategoryKind.income
                                : CategoryKind.expense),
                  ))
                    DropdownMenuItem(
                      value: c.id.value,
                      child: Text(
                        _categoryLabel(_catalog!, c),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (_busy || _postingFrozen)
                    ? null
                    : (value) => setState(() {
                        _categoryId = value ?? '';
                        _queueDraft();
                      }),
              ),
            const SizedBox(height: 14),
            if (!_transfer && _merchantCatalog != null)
              _MerchantPicker(
                key: ValueKey('merchant-picker-$_income'),
                catalog: _merchantCatalog!,
                selected: _merchantId,
                enabled: !_busy && !_postingFrozen,
                onChanged: (value) => setState(() {
                  _merchantId = value;
                  _queueDraft();
                }),
              ),
            if (!_transfer &&
                _tagCatalog != null &&
                _tagCatalog!.tags.any((t) => !t.archived)) ...[
              const Text('標籤（可複選，最多 16 個）'),
              Wrap(
                spacing: 8,
                children: [
                  for (final tag in _tagCatalog!.tags.where((t) => !t.archived))
                    FilterChip(
                      label: Text(tag.name),
                      selected: _selectedTags.contains(tag.id),
                      onSelected: (_busy || _postingFrozen)
                          ? null
                          : (selected) => setState(() {
                              if (!selected) {
                                _selectedTags.remove(tag.id);
                              } else if (_selectedTags.length < 16) {
                                _selectedTags.add(tag.id);
                              } else {
                                _message = '一筆交易最多選擇 16 個標籤。';
                              }
                              _queueDraft();
                            }),
                    ),
                ],
              ),
              const SizedBox(height: 14),
            ],
          ],
          Text(
            _draftSaveError != null
                ? '草稿保存失敗，請重試；尚未安全保存。'
                : _draftWrites > 0
                ? '正在加密保存草稿…'
                : _entryDraft == null
                ? '輸入後會自動保存本機草稿。'
                : _postingFrozen
                ? '上次送出尚待確認；欄位暫時鎖定，避免重複儲存。'
                : '草稿已加密保存；尚未影響餘額。',
            key: const Key('draft-status'),
          ),
          _button(
            _postingFrozen
                ? '確認上次送出'
                : _noteTarget != null
                ? '儲存備註'
                : _reversal != null
                ? '撤銷這筆交易'
                : _correction != null
                ? '送出更正'
                : _refund != null
                ? '儲存退款'
                : _transfer
                ? '儲存轉帳'
                : '儲存收支',
            _savePosting,
          ),
          if (_postingFrozen)
            _button(
              '返回編輯草稿',
              () => _perform(() async {
                await _engine!.reopenEntryDraft();
                final saved = await _engine!.entryDraft();
                if (mounted) setState(() => _entryDraft = saved);
              }),
            ),

          if (_entryDraft != null || _draftSaveError != null)
            TextButton(
              onPressed: _busy ? null : _discardDraft,
              child: const Text('捨棄草稿'),
            ),
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
      case _Page.simpleImport:
        return _simpleImportContent();
      case _Page.simpleExport:
        return _simpleExportContent();
      case _Page.home:
        return [
          if (widget.appPin != null && _deviceUnlockEnabled)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(
                      () => _page = _pinEnabled
                          ? _Page.pinDisable
                          : _Page.pinSetup,
                    ),
              child: Text(_pinEnabled ? '停用 App PIN' : '設定 App PIN'),
            ),
          Text('我的帳本', style: Theme.of(context).textTheme.headlineSmall),
          if (widget.deviceUnlock != null && _deviceUnlockEnabled)
            TextButton(
              onPressed: _busy ? null : _disableDeviceUnlock,
              child: const Text('停用這台手機的裝置解鎖'),
            ),
          const SizedBox(height: 12),
          if (_accounts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('先新增一個帳戶，就可以開始記帳。'),
            ),
          for (final s in _accounts)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FinancialSummary(
                  title: s.account.name,
                  subtitle: switch (s.account.kind) {
                    AccountKind.cash => '現金',
                    AccountKind.bank => '銀行',
                    AccountKind.creditCard => '信用卡負債',
                  },
                  money: s.balance,
                  privacy: _privacy,
                  kind: MoneyKind.balance,
                  moneyKey: ValueKey('account-money-${s.account.id.value}'),
                ),
              ),
            ),
          const SizedBox(height: 16),
          if (_entryDraft != null || _draftUnreadable) ...[
            Text(_draftUnreadable ? '本機草稿無法驗證，已保留檔案；請先處理。' : '有一份尚未完成的本機草稿。'),
            if (!_draftUnreadable) _button('繼續草稿', _resumeDraft),
            TextButton(
              onPressed: _busy ? null : _discardDraft,
              child: const Text('捨棄草稿'),
            ),
          ],
          _button(
            '記一筆',
            _entryDraft == null &&
                    !_draftUnreadable &&
                    _accounts.any(
                      (s) =>
                          s.account.state == AccountState.active &&
                          s.account.kind != AccountKind.creditCard,
                    )
                ? () => _edit(_Page.posting)
                : null,
          ),
          if (_engine!.capabilities.transfers)
            _button(
              _engine!.capabilities.crossCurrencyTransfers ? '轉帳' : '同幣轉帳',
              _entryDraft == null &&
                      !_draftUnreadable &&
                      _accounts.any(
                        (a) =>
                            a.account.state == AccountState.active &&
                            a.account.kind != AccountKind.creditCard,
                      )
                  ? () => _edit(_Page.posting, transfer: true)
                  : null,
            ),
          OutlinedButton(
            onPressed: _busy ? null : () => _edit(_Page.account),
            child: const Text('新增帳戶'),
          ),
          if (_engine!.capabilities.creditCards &&
              _accounts.any(
                (row) =>
                    row.account.state == AccountState.active &&
                    row.account.kind == AccountKind.creditCard,
              ))
            OutlinedButton(
              onPressed: _busy || _entryDraft != null || _draftUnreadable
                  ? null
                  : () => _edit(_Page.cardPurchase),
              child: const Text('信用卡刷卡入帳'),
            ),
          if (_engine!.capabilities.creditCards &&
              _accounts.any(
                (card) =>
                    card.account.kind == AccountKind.creditCard &&
                    card.account.state == AccountState.active &&
                    card.balance.minorUnits < BigInt.zero &&
                    _accounts.any(
                      (bank) =>
                          bank.account.kind == AccountKind.bank &&
                          bank.account.state == AccountState.active &&
                          bank.account.currency == card.account.currency,
                    ),
              ))
            OutlinedButton(
              onPressed: _busy || _entryDraft != null || _draftUnreadable
                  ? null
                  : () => _edit(_Page.cardPayment),
              child: const Text('信用卡繳款'),
            ),
          if (_engine!.capabilities.cardStatements &&
              _accounts.any(
                (row) => row.account.kind == AccountKind.creditCard,
              ))
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _page = _Page.cardStatements),
              child: const Text('信用卡帳單'),
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
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => setState(() => _page = _Page.search),
            child: const Text('搜尋交易'),
          ),
          const SizedBox(height: 12),
          Text('本月收支', style: Theme.of(context).textTheme.titleLarge),
          if (_monthlyOverflow)
            const Text('本月合計超過可表示範圍，暫不顯示報表；帳本交易仍保留。')
          else if (_monthlyReport?.currencies.isEmpty ?? true)
            const Text('本月尚無收入或支出。')
          else ...[
            for (final summary in _monthlyReport!.currencies) ...[
              Text(summary.currency.code),
              FinancialSummary(
                title: '收入',
                subtitle: _monthlyReport!.month.toString(),
                money: summary.income,
                privacy: _privacy,
                kind: MoneyKind.transaction,
                moneyKey: ValueKey('monthly-income-${summary.currency.code}'),
              ),
              FinancialSummary(
                title: '淨支出',
                subtitle: '退款與撤銷在發生月份沖減',
                money: summary.expense,
                privacy: _privacy,
                kind: MoneyKind.transaction,
                moneyKey: ValueKey('monthly-expense-${summary.currency.code}'),
              ),
            ],
          ],
          if (_monthlyReport != null)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _page = _Page.monthlyReport),
              child: const Text('查看月收支明細'),
            ),
          if (_engine!.capabilities.budgets)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _page = _Page.budgets),
              child: const Text('月預算'),
            ),
          if (_engine!.capabilities.recurring)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _page = _Page.recurring),
              child: const Text('定期交易'),
            ),
          if (_engine!.capabilities.recurring && _recurringReminderError)
            const Text('定期交易提醒無法更新，請開啟定期交易檢查。'),
          if (_engine!.capabilities.recurring && (_recurringDueCount ?? 0) > 0)
            Text(
              _privacy == PrivacyMode.hidden
                  ? '有定期交易待確認。'
                  : '有 $_recurringDueCount 筆定期交易待確認。',
            ),
          const SizedBox(height: 12),
          if (_accounts.isNotEmpty) ...[
            Text('資產摘要', style: Theme.of(context).textTheme.titleLarge),
            const Text('只合計目前現金與銀行帳戶餘額；逐幣別顯示，尚無跨幣估值或投資資產。'),
            if (_assetOverflow)
              const Text('帳戶合計超過可表示範圍，暫不顯示資產摘要；個別帳戶餘額仍保留。')
            else if (_assetReport?.currencies.isEmpty ?? true)
              const Text('沒有納入摘要的帳戶。')
            else
              for (final summary in _assetReport!.currencies)
                FinancialSummary(
                  title: '${summary.currency.code} 帳戶餘額',
                  subtitle: '含期初餘額；個別帳戶見上方',
                  money: summary.total,
                  privacy: _privacy,
                  kind: MoneyKind.balance,
                  moneyKey: ValueKey('asset-total-${summary.currency.code}'),
                ),
            if ((_assetReport?.excludedCount ?? 0) > 0)
              Text('另有 ${_assetReport!.excludedCount} 個帳戶設定為不納入摘要。'),
            const SizedBox(height: 12),
          ],
          Text('最近交易', style: Theme.of(context).textTheme.titleLarge),
          if (_entries.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('尚無交易')),
          for (final e in _entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  e.kind == PostingKind.reversal
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _reversalSummary(e, _accountName, _privacy),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _showActivity(e.id),
                              child: const Text('查看活動'),
                            ),
                          ],
                        )
                      : e.kind == PostingKind.transfer
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (e.correctedBy != null)
                              const Text('已更正；原交易、沖回與替代交易均保留')
                            else if (e.reversedBy != null)
                              const Text('已撤銷；反向紀錄另列'),
                            if (e.reversedBy == null &&
                                _engine!.capabilities.reversals)
                              TextButton(
                                key: ValueKey('entry-reverse-${e.id}'),
                                onPressed: _busy
                                    ? null
                                    : () => _startReversal(e.id),
                                child: const Text('撤銷交易'),
                              ),
                            if (e.reversedBy == null &&
                                _engine!.capabilities.corrections)
                              TextButton(
                                key: ValueKey('entry-correct-${e.id}'),
                                onPressed: _busy
                                    ? null
                                    : () => _startCorrection(e.id),
                                child: const Text('更正交易'),
                              ),
                            if (e.reversedBy == null &&
                                e.correctedBy == null &&
                                _engine!.capabilities.tombstones)
                              TextButton(
                                key: ValueKey('entry-tombstone-${e.id}'),
                                onPressed: _busy
                                    ? null
                                    : () => _startTombstone(e.id),
                                child: const Text('刪除交易'),
                              ),
                            TransferSummary(
                              entry: e,
                              source: _accountName(e.accountId),
                              destination: _accountName(e.destinationId),
                              privacy: _privacy,
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                key: ValueKey('entry-activity-${e.id}'),
                                onPressed: _busy
                                    ? null
                                    : () => _showActivity(e.id),
                                child: const Text('查看活動'),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FinancialSummary(
                              title:
                                  '${_kindLabel(e.kind)} · ${_accounts.where((a) => a.account.id == e.accountId).firstOrNull?.account.name ?? '帳戶'}',
                              subtitle:
                                  '${e.date}${_entryCategories[e.id] == null ? '' : ' · ${_allocationLabel(e.id)}'}${_entryTags[e.id] == null ? '' : ' · ${_entryTags[e.id]}'}${_entryMerchants[e.id] == null ? '' : ' · ${_entryMerchants[e.id]}'}',
                              money: e.amount,
                              privacy: _privacy,
                              kind: MoneyKind.transaction,
                              moneyKey: ValueKey('entry-money-${e.id.value}'),
                              action: PopupMenuButton<String>(
                                key: ValueKey('entry-actions-${e.id}'),
                                tooltip: '交易操作',
                                enabled: !_busy,
                                onSelected: (action) => switch (action) {
                                  'activity' => _showActivity(e.id),
                                  'refund' => _startRefund(e.id),
                                  'reversal' => _startReversal(e.id),
                                  'correction' => _startCorrection(e.id),
                                  'tombstone' => _startTombstone(e.id),
                                  _ => _copyPosting(e.id),
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'activity',
                                    child: Text('查看活動'),
                                  ),
                                  if (_engine!.capabilities.reversals &&
                                      e.reversedBy == null &&
                                      [
                                        PostingKind.income,
                                        PostingKind.expense,
                                      ].contains(e.kind))
                                    const PopupMenuItem(
                                      value: 'reversal',
                                      child: Text('撤銷交易'),
                                    ),
                                  if (_engine!.capabilities.corrections &&
                                      e.reversedBy == null &&
                                      [
                                        PostingKind.income,
                                        PostingKind.expense,
                                      ].contains(e.kind))
                                    const PopupMenuItem(
                                      value: 'correction',
                                      child: Text('更正交易'),
                                    ),
                                  if (_engine!.capabilities.tombstones &&
                                      e.reversedBy == null &&
                                      e.correctedBy == null &&
                                      [
                                        PostingKind.income,
                                        PostingKind.expense,
                                      ].contains(e.kind))
                                    const PopupMenuItem(
                                      value: 'tombstone',
                                      child: Text('刪除交易'),
                                    ),
                                  if ([
                                    PostingKind.income,
                                    PostingKind.expense,
                                  ].contains(e.kind))
                                    const PopupMenuItem(
                                      value: 'copy',
                                      child: Text('再記一筆類似交易'),
                                    ),
                                  if (e.kind == PostingKind.expense &&
                                      _engine!.capabilities.refunds &&
                                      e.reversedBy == null)
                                    const PopupMenuItem(
                                      value: 'refund',
                                      child: Text('記錄退款'),
                                    ),
                                ],
                              ),
                            ),
                            if (e.correctedBy != null)
                              const Text('已更正；原交易、沖回與替代交易均保留')
                            else if (e.reversedBy != null)
                              const Text('已撤銷；反向紀錄另列'),
                            if (e.refundOf != null) ..._refundDetails(e),
                            ..._splitDetails(e.id),
                          ],
                        ),
                  if (_engine!.capabilities.notes) ..._noteSummary(e),
                ],
              ),
            ),
          if (_hasMore)
            TextButton(
              onPressed: _busy ? null : _more,
              child: const Text('載入更多'),
            ),
          if (_deletedEntries.isNotEmpty) ...[
            const Divider(),
            Text('已刪除交易', style: Theme.of(context).textTheme.titleLarge),
            const Text('僅供查閱歷史；不計入目前餘額。'),
            for (final e in _deletedEntries)
              ListTile(
                key: ValueKey('deleted-entry-${e.id}'),
                title: Text('${_kindLabel(e.kind)} · ${e.date}'),
                subtitle: e.tombstoneReason?.isNotEmpty == true
                    ? Text(
                        _privacy == PrivacyMode.hidden
                            ? '原因已隱藏'
                            : e.tombstoneReason!,
                      )
                    : const Text('交易已刪除'),
                trailing: TextButton(
                  onPressed: _busy ? null : () => _showActivity(e.id),
                  child: const Text('查看活動'),
                ),
              ),
            if (_hasMoreDeleted)
              TextButton(
                onPressed: _busy ? null : _moreDeleted,
                child: const Text('載入更多已刪除交易'),
              ),
          ],
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
          TextButton(
            onPressed: _busy ? null : _chooseSimpleImport,
            child: const Text('匯入簡易收支檔'),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() => _page = _Page.simpleExport),
            child: const Text('匯出簡易收支檔'),
          ),
          const SizedBox(height: 16),
          const Text(
            '目前上限：32 個帳戶、5,000 筆交易（含期初）、256 個分類、256 個標籤、256 個商家。另支援最多 5,000 次備註修訂。',
            style: TextStyle(color: Colors.grey),
          ),
        ];
    }
  }
}

String _kindLabel(PostingKind kind) => switch (kind) {
  PostingKind.opening => '期初',
  PostingKind.income => '收入',
  PostingKind.expense => '支出',
  PostingKind.transfer => '轉帳',
  PostingKind.refund => '退款',
  PostingKind.reversal => '撤銷',
};
String _error(Object error) => switch (error) {
  PreviewDataUnavailable() => '帳本密碼已通過，但本機帳本或安全設定完整性無法確認。已停止財務操作；請保留目前資料與加密備份。',
  AppPinRejected() => 'App PIN 或裝置認證未通過；五次 PIN 錯誤後請用帳本密碼解鎖，停用本機裝置解鎖。帳本未變更。',
  FormatException(message: 'App PIN format') => 'App PIN 需為 6–12 位數字。',
  FormatException(message: 'App PIN confirmation') => '兩次 App PIN 不一致。',
  PlatformException(code: 'simple_export') =>
    '簡易匯出寫入或回讀核對失敗；請檢查並刪除可能不完整的檔案，再重試。',
  ExchangeException(code: 'empty_export') => '目前沒有可匯出的普通收入或支出。完整帳本請使用加密備份。',
  ExchangeException(code: 'same_workspace_import') =>
    '不能把這本帳的簡易匯出再匯入同一本帳，避免重複入帳。請使用另一個 V2 帳本。',
  ExchangeException(code: 'source_conflict', row: final row) =>
    '檔案第 $row 筆與先前匯入的同來源資料不同；整批未寫入。',
  ExchangeException(row: final row) =>
    '匯入檔案或帳戶對應無效${row == null ? '' : '（第 $row 筆）'}；請檢查後重試。',
  PlatformException(code: 'document') => '無法讀取所選檔案；請確認檔案仍可存取且為 UTF-8。',
  NoteException(code: NoteError.conflict) => '備註已有新版本。請查看活動，再讀取最新版本並確認你的草稿。',
  NoteException(code: NoteError.unchanged) => '備註內容沒有變更；可返回編輯或捨棄草稿。',
  NoteException() => '備註格式或交易不符；最多 1024 個字元。',

  LedgerException(code: LedgerError.reversalDependency) =>
    '交易已有退款、撤銷或更正紀錄，不能再對原交易操作。',
  LedgerException(code: LedgerError.reversalReference) =>
    '僅能撤銷完整的收入、支出或轉帳；日期不可早於原交易。',
  LedgerException(code: LedgerError.correctionReference) =>
    '只能把完整收入、支出或轉帳更正為相同種類；請重新確認原交易。',
  LedgerException(code: LedgerError.tombstoneDependency) =>
    '交易已有後續紀錄或已刪除，不能再次刪除；請查看活動。',
  LedgerException(code: LedgerError.tombstoneReference) =>
    '原交易資料已變更或不適用一般刪除；請重新整理後確認。',
  LedgerException(code: LedgerError.refundLimit) => '退款超過原支出或該分類剩餘可退金額，請重新確認。',
  LedgerException(code: LedgerError.refundReference) =>
    '退款須對應原支出及原分類，日期不可早於原支出。',
  PreviewSplitInvalid() => '請為每項拆分選擇不同且可用的分類，至少 2 項。',
  LedgerException(code: LedgerError.allocationMismatch) =>
    '拆分合計必須等於交易總額；請確認各項金額。',
  DraftNeedsResolution() => '請先繼續或捨棄本機草稿，再進行此操作。',
  DraftUnavailable() => '草稿無法驗證，原檔已保留；請勿清除 App 資料。',

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
  PreviewCapacity() => '已達目前容量上限，請先處理本機草稿，再匯出備份。',
  MoneyException() => '金額格式、精度或大小不符。請輸入該幣別可接受的金額。',
  AccountException() => '帳戶或日期不符：日期不可早於帳戶起始日，名稱不能空白。',
  PreviewTransferAccountInvalid() => '請選擇可用的轉出與轉入帳戶。',
  LedgerException(code: LedgerError.sameAccount) => '轉出與轉入必須是不同帳戶。',
  LedgerException(code: LedgerError.invalidAmount) =>
    '收支或轉帳本金必須大於 0；手續費可為 0，但不能為負數。',
  LedgerException() => '請檢查帳戶、金額與幣別；同幣轉帳的兩個帳戶必須同幣。',
  BackupException() => '密碼／救援文字不符、檔案損壞，或設定密碼不足 12 個字元。',
  FormatException() => '請確認日期為 YYYY-MM-DD，兩次設定密碼相同。',
  PreviewInvalid() => '設定或備份不符合試用版支援範圍。原資料已保留。',
  _ => '操作未能完成。請保留原資料與備份，解鎖後確認結果；不要清除 App 資料。',
};
