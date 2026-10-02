import 'dart:io';
import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:market_data/market_data.dart';
import 'package:workmanager/workmanager.dart';

import 'platform_services.dart';
import 'price_alert_service.dart';

const _taskName = 'expense-v2-background-price-alert';
const _uniquePrefix = 'expense-v2-price-alert-';
const _instrumentIdKey = 'instrumentId';

final class AndroidPriceAlertBackgroundScheduler
    implements PriceAlertBackgroundScheduler {
  AndroidPriceAlertBackgroundScheduler({Workmanager? workmanager})
    : _workmanager = workmanager ?? Workmanager();

  final Workmanager _workmanager;

  static Future<void> initialize() async {
    if (Platform.isAndroid) {
      await Workmanager().initialize(priceAlertCallbackDispatcher);
    }
  }

  @override
  bool supports(InvestmentInstrument instrument) =>
      Platform.isAndroid && YahooChartIntradayGateway().supports(instrument);

  @override
  Future<bool> synchronize(SavedPriceAlert saved) async {
    final instrument = saved.instrument;
    if (instrument == null ||
        !saved.backgroundEnabled ||
        !supports(instrument)) {
      await cancel(saved.alert.instrumentId);
      return true;
    }
    final notifications = FlutterLocalNotificationsPlugin();
    await notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_launcher'),
      ),
    );
    final android = notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final allowed = await android?.requestNotificationsPermission();
    if (allowed == false) return false;
    await _workmanager.registerPeriodicTask(
      _uniqueName(instrument.id),
      _taskName,
      frequency: const Duration(minutes: 15),
      inputData: {_instrumentIdKey: instrument.id.value},
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 15),
      tag: 'expense-v2-price-alerts',
    );
    return true;
  }

  @override
  Future<void> cancel(PublicId instrumentId) =>
      _workmanager.cancelByUniqueName(_uniqueName(instrumentId));
}

String _uniqueName(PublicId instrumentId) =>
    '$_uniquePrefix${instrumentId.value}';

@pragma('vm:entry-point')
void priceAlertCallbackDispatcher() {
  DartPluginRegistrant.ensureInitialized();
  Workmanager().executeTask((task, inputData) async {
    if (task != _taskName) return true;
    final rawId = inputData?[_instrumentIdKey];
    if (rawId is! String) return true;
    try {
      final instrumentId = PublicId.parse(rawId);
      final service = PriceAlertService(AndroidPriceAlertRecordStore());
      final saved = await service.loadById(instrumentId);
      final instrument = saved?.instrument;
      if (saved == null ||
          instrument == null ||
          !saved.backgroundEnabled ||
          !saved.alert.enabled) {
        return true;
      }
      final gateway = YahooChartIntradayGateway();
      if (!gateway.supports(instrument)) return true;
      final result = await gateway.latestBar(
        instrument,
        interval: IntradayInterval.fiveMinutes,
      );
      final evaluation = await service.evaluateIntraday(
        instrument: instrument,
        result: result,
        providerId: YahooChartIntradayStockProvider.providerId,
        now: UtcInstant(DateTime.now().toUtc()),
      );
      final notification = evaluation?.notification;
      if (notification != null) {
        await _BackgroundPriceAlertNotifications().show(notification);
      }
    } catch (_) {
      // Periodic work is best-effort. A malformed local record or a temporary
      // provider failure must not create an aggressive retry loop.
    }
    return true;
  });
}

final class _BackgroundPriceAlertNotifications {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> show(PriceAlertNotification notification) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_launcher'),
      ),
    );
    await _plugin.show(
      id: _notificationId(notification.alertId.value),
      title: '到價提醒：${notification.symbol}',
      body:
          '目前 ${notification.price} ${notification.currency.code}，已跨越你設定的價格門檻。',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'expense_v2_price_alerts_v1',
          '投資到價提醒',
          channelDescription: '使用免金鑰行情來源，在背景定期檢查使用者設定的價格門檻。',
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.secret,
        ),
      ),
      payload: notification.instrumentId.value,
    );
  }
}

int _notificationId(String value) {
  // Match java.lang.String.hashCode used by the foreground notifier so a
  // rare foreground/background race replaces rather than duplicates a card.
  var hash = 0;
  for (final codeUnit in value.codeUnits) {
    hash = (31 * hash + codeUnit) & 0xffffffff;
  }
  return hash >= 0x80000000 ? hash - 0x100000000 : hash;
}
