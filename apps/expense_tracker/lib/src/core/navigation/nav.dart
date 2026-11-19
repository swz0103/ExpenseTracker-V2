import 'package:flutter/widgets.dart';

import '../platform/sync_job.dart';
import '../ledger/ledger.dart';

/// The pages under 更多, each opened over the tab with a back arrow.
enum MoreDestination {
  reports,
  investments,
  debts,
  budgets,
  recurring,
  categories,
  settings,
  tags,
}

/// The pages under 定期交易, each with a back arrow to it.
enum RecurringView { manage, subscriptions, paused }

/// The pages under 設定與資料, each with a back arrow to it.
enum SettingsDestination {
  backup('備份與還原'),
  importExport('匯入與匯出'),
  reminders('通知與提醒'),
  security('安全'),
  appearance('外觀與操作'),
  about('關於'),
  trash('最近刪除');

  const SettingsDestination(this.label);

  final String label;
}

/// A page the app frame can open: a [MoreDestination], an account or a holding.
/// Typed, so a page is told what it shows rather than parsing a key, and
/// the frame can check the account or holding is still there.
sealed class AppRoute {
  const AppRoute();

  /// Where back leads from here; null for the tab underneath.
  AppRoute? get parent => null;
}

final class SectionRoute extends AppRoute {
  const SectionRoute(this.section);

  final MoreDestination section;

  @override
  bool operator ==(Object other) =>
      other is SectionRoute && other.section == section;

  @override
  int get hashCode => section.hashCode;
}

/// An account's page; a card's shows its statement.
final class AccountRoute extends AppRoute {
  const AccountRoute(this.id);

  final String id;

  @override
  bool operator ==(Object other) => other is AccountRoute && other.id == id;

  @override
  int get hashCode => Object.hash(AccountRoute, id);
}

/// A holding's page, which returns to 投資.
final class HoldingRoute extends AppRoute {
  const HoldingRoute(this.code);

  final String code;

  @override
  AppRoute get parent => AppRoutes.investments;

  @override
  bool operator ==(Object other) => other is HoldingRoute && other.code == code;

  @override
  int get hashCode => Object.hash(HoldingRoute, code);
}

/// A person paid for, or a loan, opened from 代墊與借貸 and returning
/// to it.
final class DebtRoute extends AppRoute {
  const DebtRoute(this.id);

  final String id;

  @override
  AppRoute get parent => AppRoutes.debts;

  @override
  bool operator ==(Object other) => other is DebtRoute && other.id == id;

  @override
  int get hashCode => Object.hash(DebtRoute, id);
}

/// 標籤與商家 on its 商家 half: where a merchant's page goes back to.
final class MerchantsRoute extends AppRoute {
  const MerchantsRoute();
}

/// A tag's page, or a merchant's, which returns to 標籤與商家 on the
/// half it came from.
final class TagRoute extends AppRoute {
  const TagRoute(this.name, {this.merchant = false});

  final String name;
  final bool merchant;

  @override
  AppRoute get parent => merchant ? const MerchantsRoute() : AppRoutes.tags;

  @override
  bool operator ==(Object other) =>
      other is TagRoute && other.name == name && other.merchant == merchant;

  @override
  int get hashCode => Object.hash(TagRoute, name, merchant);
}

/// A page of 設定與資料, which returns to it.
final class SettingsRoute extends AppRoute {
  const SettingsRoute(this.part);

  final SettingsDestination part;

  @override
  AppRoute get parent => AppRoutes.settings;

  @override
  bool operator ==(Object other) =>
      other is SettingsRoute && other.part == part;

  @override
  int get hashCode => Object.hash(SettingsRoute, part);
}

/// A page of 定期交易, which returns to it.
final class RecurringRoute extends AppRoute {
  const RecurringRoute(this.view);

  final RecurringView view;

  @override
  AppRoute get parent => AppRoutes.recurring;

  @override
  bool operator ==(Object other) =>
      other is RecurringRoute && other.view == view;

  @override
  int get hashCode => Object.hash(RecurringRoute, view);
}

/// The places pages open, by name.
abstract final class AppRoutes {
  static const reports = SectionRoute(MoreDestination.reports);
  static const investments = SectionRoute(MoreDestination.investments);
  static const debts = SectionRoute(MoreDestination.debts);
  static const budgets = SectionRoute(MoreDestination.budgets);
  static const recurring = SectionRoute(MoreDestination.recurring);
  static const categories = SectionRoute(MoreDestination.categories);
  static const settings = SectionRoute(MoreDestination.settings);
  static const tags = SectionRoute(MoreDestination.tags);

  static AppRoute account(String id) => AccountRoute(id);
  static AppRoute holding(String code) => HoldingRoute(code);
  static AppRoute debt(String id) => DebtRoute(id);
  static AppRoute tag(String name) => TagRoute(name);
  static AppRoute merchant(String name) => TagRoute(name, merchant: true);
  static AppRoute settingsPart(SettingsDestination part) => SettingsRoute(part);
  static AppRoute recurringView(RecurringView view) => RecurringRoute(view);
}

/// What a page may ask of the app frame.
final class Nav {
  const Nav({
    required this.open,
    required this.back,
    required this.compose,
    required this.showEntry,
    this.market,
    this.saveFile,
  });

  /// Opens a page from [AppRoutes].
  final ValueChanged<AppRoute> open;

  /// Returns from an opened page.
  final VoidCallback back;

  /// Opens the composer for a new entry of `type`, filled in from
  /// `draft` if given, or to show and edit `entry`.
  final Future<void> Function({EntryType type, Entry? entry, Entry? draft})
  compose;

  /// Shows an entry's details, with delete and edit.
  final ValueChanged<Entry> showEntry;

  /// Closing prices and rates, to refresh and to say how they stand; none
  /// in the preview.
  final SyncJob? market;

  /// Each stock's past daily closes, when [market] keeps them.
  PriceHistory? get prices => switch (market) {
    final PriceHistory history => history,
    _ => null,
  };

  /// Hands a file made on the page, such as a report as a picture, to the
  /// person to keep outside the app; false when they cancel. None in the
  /// preview.
  final Future<bool> Function(String name, List<int> bytes)? saveFile;
}
