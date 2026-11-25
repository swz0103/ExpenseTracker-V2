/// The contribution points the app's screens read and modules add to,
/// on the kernel's registry: `contributions.on(point).add(owner, item)`.
///
/// The five the prototypes proved: settings and search items, overview
/// blocks, the composer's kinds and fields (design D, Amenders), with the
/// balance sheet's rows ([sheetClaims]) and [valuers], which the core
/// reads and the kernel therefore declares. The rest are declared for the
/// modules still to move; each item's shape is provisional until its
/// first user (docs/architecture.md, 模組).
library;

import 'package:flutter/widgets.dart';
import 'package:kernel/kernel.dart';

import 'composer.dart';
import 'setting_topic.dart';

export 'composer.dart';

/// A page of 設定, by key: the app's own pages and any a module adds.
extension type const SettingsPageKey(String value) implements Object {}

/// A setting a module adds to a page of 設定: the card [build] draws,
/// found by search through [topic] (the page wraps it in its Findable).
final class SettingsItem {
  const SettingsItem({
    required this.page,
    required this.topic,
    required this.build,
  });

  final SettingsPageKey page;
  final SettingTopic topic;
  final WidgetBuilder build;
}

/// A block of 總覽 a module adds: [key] keeps its place in the order the
/// person chose, [title] names it in the order's editor.
final class OverviewBlockItem {
  const OverviewBlockItem({
    required this.key,
    required this.title,
    required this.build,
  });

  final String key;
  final String title;
  final WidgetBuilder build;
}

/// A mark on a row of the entries' list for intents of [kind], such as
/// a loan payment's 還款 (declared; no user yet).
final class EntryMark {
  const EntryMark({required this.kind, required this.build});

  final IntentType kind;
  final Widget Function(BuildContext context, IntentId intent) build;
}

/// The page that edits an intent of [kind] kept outside the composer,
/// such as a stock split (declared; no user yet).
final class IntentEditor {
  const IntentEditor({required this.kind, required this.open});

  final IntentType kind;
  final Future<void> Function(BuildContext context, IntentId intent) open;
}

/// A column an import reads into [slot] of a draft, by the [headers] a
/// file may give it (declared; no user yet).
final class ImportColumn {
  const ImportColumn({
    required this.headers,
    required this.slot,
    required this.read,
  });

  final List<String> headers;
  final Slot<Object> slot;
  final Object? Function(String cell) read;
}

/// What a composer suggests for [slot] from the draft so far, such as a
/// rate, a fee or a tax (declared; no user yet).
final class FormDefault {
  const FormDefault({required this.slot, required this.suggest});

  final Slot<Object> slot;
  final Object? Function(Draft draft) suggest;
}

/// The reminders a module asks for on a day (declared; no user yet).
final class ReminderSource {
  const ReminderSource({required this.key, required this.due});

  final String key;
  final List<({Day day, String said})> Function(Day today) due;
}

/// A check of the book a module adds to 檢查帳本 (declared; no user yet).
final class IntegrityCheck {
  const IntegrityCheck({required this.key, required this.problems});

  final String key;
  final List<String> Function(BookReader reader) problems;
}

/// A module's table kept in the backup, with its own [version]
/// (declared; no user yet).
final class BackupSection {
  const BackupSection({
    required this.key,
    required this.version,
    required this.write,
    required this.read,
  });

  final String key;
  final int version;
  final Object? Function() write;
  final void Function(Object? kept, int version) read;
}

/// A budget's scope a module offers: which accounts' spending counts
/// (declared; no user yet).
final class BudgetScope {
  const BudgetScope({
    required this.key,
    required this.label,
    required this.accounts,
  });

  final String key;
  final String label;
  final Set<AccountId> Function(AccountTree tree) accounts;
}

/// Every point of the shell, by name.
abstract final class ShellPoints {
  static const settings = ContributionPoint<SettingsItem>('shell.settings');
  static const overview = ContributionPoint<OverviewBlockItem>(
    'shell.overview',
  );
  static const composerKinds = ContributionPoint<EntryKind>(
    'shell.composer.kinds',
  );
  static const composerFields = ContributionPoint<ComposerField<Object>>(
    'shell.composer.fields',
  );

  // Declared for the modules still to move; no contribution yet.
  static const entryMarks = ContributionPoint<EntryMark>('shell.entryMarks');
  static const editors = ContributionPoint<IntentEditor>('shell.editors');
  static const importColumns = ContributionPoint<ImportColumn>(
    'shell.importColumns',
  );
  static const formDefaults = ContributionPoint<FormDefault>(
    'shell.formDefaults',
  );
  static const reminders = ContributionPoint<ReminderSource>('shell.reminders');
  static const integrity = ContributionPoint<IntegrityCheck>('shell.integrity');
  static const backupSections = ContributionPoint<BackupSection>(
    'shell.backupSections',
  );
  static const budgetScopes = ContributionPoint<BudgetScope>(
    'shell.budgetScopes',
  );

  /// Every point of the shell, for a test that no two share a name.
  static const all = <ContributionPoint<Object?>>[
    settings,
    overview,
    composerKinds,
    composerFields,
    entryMarks,
    editors,
    importColumns,
    formDefaults,
    reminders,
    integrity,
    backupSections,
    budgetScopes,
  ];
}
