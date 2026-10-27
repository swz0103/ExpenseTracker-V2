import 'package:flutter/widgets.dart';

import 'connector.dart';
import 'ledger/ledger.dart';

/// The pages under 更多, each opened over the tab with a back arrow.
enum Section {
  reports,
  investments,
  budgets,
  recurring,
  categories,
  settings,
  labels,
}

/// The pages under 設定與資料, each with a back arrow to it.
enum SettingsPart {
  backup('備份與還原'),
  exchange('匯入與匯出'),
  reminders('通知與提醒'),
  security('安全'),
  appearance('外觀與操作'),
  about('關於');

  const SettingsPart(this.label);

  final String label;
}

/// A page the app frame can open: a [Section], an account or a holding.
/// Typed, so a page is told what it shows rather than parsing a key, and
/// the frame can check the account or holding is still there.
sealed class Place {
  const Place();

  /// Where back leads from here; null for the tab underneath.
  Place? get parent => null;
}

final class SectionPlace extends Place {
  const SectionPlace(this.section);

  final Section section;

  @override
  bool operator ==(Object other) =>
      other is SectionPlace && other.section == section;

  @override
  int get hashCode => section.hashCode;
}

/// An account's page; a card's shows its statement.
final class AccountPlace extends Place {
  const AccountPlace(this.id);

  final String id;

  @override
  bool operator ==(Object other) => other is AccountPlace && other.id == id;

  @override
  int get hashCode => Object.hash(AccountPlace, id);
}

/// A holding's page, which returns to 投資.
final class HoldingPlace extends Place {
  const HoldingPlace(this.code);

  final String code;

  @override
  Place get parent => Pages.investments;

  @override
  bool operator ==(Object other) => other is HoldingPlace && other.code == code;

  @override
  int get hashCode => Object.hash(HoldingPlace, code);
}

/// A page of 設定與資料, which returns to it.
final class SettingsPlace extends Place {
  const SettingsPlace(this.part);

  final SettingsPart part;

  @override
  Place get parent => Pages.settings;

  @override
  bool operator ==(Object other) =>
      other is SettingsPlace && other.part == part;

  @override
  int get hashCode => Object.hash(SettingsPlace, part);
}

/// The places pages open, by name.
abstract final class Pages {
  static const reports = SectionPlace(Section.reports);
  static const investments = SectionPlace(Section.investments);
  static const budgets = SectionPlace(Section.budgets);
  static const recurring = SectionPlace(Section.recurring);
  static const categories = SectionPlace(Section.categories);
  static const settings = SectionPlace(Section.settings);
  static const labels = SectionPlace(Section.labels);

  static Place account(String id) => AccountPlace(id);
  static Place holding(String code) => HoldingPlace(code);
  static Place settingsPart(SettingsPart part) => SettingsPlace(part);
}

/// What a page may ask of the app frame.
final class Nav {
  const Nav({
    required this.open,
    required this.back,
    required this.compose,
    required this.showEntry,
    this.market,
  });

  /// Opens a page from [Pages].
  final ValueChanged<Place> open;

  /// Returns from an opened page.
  final VoidCallback back;

  /// Opens the composer for a new entry of [type], filled in from
  /// [draft] if given, or to show and edit [entry].
  final Future<void> Function({EntryType type, Entry? entry, Entry? draft})
  compose;

  /// Shows an entry's details, with delete and edit.
  final ValueChanged<Entry> showEntry;

  /// Closing prices and rates, to refresh and to say how they stand; none
  /// in the preview.
  final Connector? market;
}
