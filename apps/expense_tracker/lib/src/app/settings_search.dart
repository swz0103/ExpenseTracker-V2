import 'package:flutter/material.dart';

import '../core/design_system/design_system.dart';
import '../core/design_system/glyphs.dart';
import '../core/design_system/shape.dart';
import '../core/design_system/spacing.dart';
import '../core/design_system/theme.dart';
import '../core/formatting/setting_topic.dart';
import '../core/navigation/nav.dart';
import '../features/backup/ui/backup_section.dart';
import '../features/entries/ui/trash_section.dart';
import '../features/import_export/ui/import_export_section.dart';
import '../features/lock/ui/security_section.dart';
import '../features/reminders/ui/reminders_section.dart';
import '../features/settings/ui/preferences_section.dart';
import 'about_section.dart';
import 'platform_services.dart';

/// A setting search found, and the page it is on.
typedef FoundSetting = ({SettingTopic topic, SettingsDestination page});

/// Every setting [page] can show, whatever the phone: each section
/// declares its settings' words beside the cards it builds (N8);
/// settings_search_rules_test fails on a card built without one.
List<SettingTopic> topicsOn(SettingsDestination page) => switch (page) {
  SettingsDestination.backup => BackupSection.topics,
  SettingsDestination.importExport => ImportExportSection.topics,
  SettingsDestination.reminders => RemindersSection.topics,
  SettingsDestination.security => SecuritySection.topics,
  SettingsDestination.appearance => AppearanceSection.topics,
  SettingsDestination.about => AboutSection.topics,
  SettingsDestination.trash => TrashSection.topics,
};

/// The settings [page] shows on this phone and build ([services]), so
/// search offers none the page then lacks (review 39 #4):
/// settings_search_rules_test fails on a topic offered but not built.
List<SettingTopic> offeredOn(
  SettingsDestination page,
  PlatformServices services,
) => switch (page) {
  SettingsDestination.backup =>
    services.backupManager == null
        ? const []
        : BackupSection.offered(drive: services.drive, phone: services.phone),
  SettingsDestination.importExport => ImportExportSection.topics,
  SettingsDestination.reminders => RemindersSection.offered(
    notifier: services.notifier,
    calendar: services.calendar,
  ),
  SettingsDestination.security => SecuritySection.offered(
    backupManager: services.backupManager,
    privacy: services.privacy,
    preferences: services.preferences,
  ),
  SettingsDestination.appearance =>
    services.preferences == null ? const [] : AppearanceSection.topics,
  SettingsDestination.about => AboutSection.offered(services),
  SettingsDestination.trash => TrashSection.topics,
};

/// Every setting, page by page, so one four taps away is found by typing
/// a word of it.
final List<FoundSetting> settingTopics = [
  for (final page in SettingsDestination.values)
    for (final topic in topicsOn(page)) (topic: topic, page: page),
];

/// The settings shown with [services], page by page.
List<FoundSetting> offeredTopics(PlatformServices services) => [
  for (final page in SettingsDestination.values)
    for (final topic in offeredOn(page, services)) (topic: topic, page: page),
];

/// The settings of [among] (every one when null) whose name or other
/// words hold [query] (SettingTopic.matches: 臺 as 台, full-width as
/// half, any case, spaces left out); none for a blank query.
List<FoundSetting> findSettings(String query, {List<FoundSetting>? among}) => [
  for (final found in among ?? settingTopics)
    if (found.topic.matches(query)) found,
];

/// A search box above the settings' first page: typing shows the
/// settings found, each opening its page on it; cleared, the page is
/// back.
class SettingsSearch extends StatefulWidget {
  const SettingsSearch({
    super.key,
    required this.child,
    required this.onOpen,
    required this.services,
  });

  /// What this phone and build offer: search lists only the settings
  /// shown with them.
  final PlatformServices services;

  /// The first page, shown while nothing is typed.
  final List<Widget> child;
  final ValueChanged<FoundSetting> onOpen;

  @override
  State<SettingsSearch> createState() => _SettingsSearchState();
}

class _SettingsSearchState extends State<SettingsSearch> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final found = findSettings(
      _text.text,
      among: offeredTopics(widget.services),
    );
    final searching = _text.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _text,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: '搜尋設定',
            isDense: true,
            filled: true,
            fillColor: AppColors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: Space.s3),
            prefixIcon: const Padding(
              padding: EdgeInsets.all(Space.s3),
              child: GlyphIcon(Glyph.search, size: 18, color: AppColors.muted),
            ),
            suffixIcon: searching
                ? IconButton(
                    tooltip: '清除搜尋',
                    onPressed: () => setState(_text.clear),
                    icon: const GlyphIcon(
                      Glyph.close,
                      size: 16,
                      color: AppColors.muted,
                    ),
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.large),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: Space.s3),
        if (!searching)
          ...widget.child
        else if (found.isEmpty)
          const Padding(
            padding: EdgeInsets.all(Space.s4),
            child: Text('找不到這個設定', style: mutedSmall),
          )
        else
          GroupBox(
            padding: const EdgeInsets.symmetric(vertical: Space.s1),
            child: Column(
              children: [
                for (final topic in found)
                  _Found(topic, onTap: () => widget.onOpen(topic)),
              ],
            ),
          ),
      ],
    );
  }
}

/// One setting found: its name, the page it is on, and an arrow.
class _Found extends StatelessWidget {
  const _Found(this.topic, {required this.onTap});

  final FoundSetting topic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TapArea(
    label: '${topic.topic.name}，在${topic.page.label}',
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s4,
        vertical: Space.s3,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              topic.topic.name,
              style: const TextStyle(
                fontSize: TextSize.body,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(topic.page.label, style: mutedSmall),
          const SizedBox(width: Space.s2),
          const GlyphIcon(Glyph.next, size: 16, color: AppColors.muted),
        ],
      ),
    ),
  );
}
