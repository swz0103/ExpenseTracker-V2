import 'package:flutter/material.dart';

import '../core/design_system/design_system.dart';
import '../core/design_system/glyphs.dart';
import '../core/design_system/shape.dart';
import '../core/design_system/spacing.dart';
import '../core/design_system/theme.dart';
import '../core/formatting/words.dart';
import '../core/messages/lock_messages.dart';
import '../core/messages/trade_messages.dart';
import '../core/navigation/nav.dart';

/// One setting as it is looked for: its name, other words for it, and
/// the page it is on.
typedef SettingTopic = ({
  String name,
  List<String> words,
  SettingsDestination page,
});

/// Every setting by name, so one four taps away is found by typing a word
/// of it. Kept beside the pages' own cards: a setting added without a line
/// here is not found.
const settingTopics = <SettingTopic>[
  (name: '雲端硬碟備份', words: ['Google', '雲端'], page: SettingsDestination.backup),
  (name: '手機資料夾備份', words: ['資料夾'], page: SettingsDestination.backup),
  (name: '匯出備份', words: ['備份檔'], page: SettingsDestination.backup),
  (name: '從備份還原', words: ['還原', '換手機'], page: SettingsDestination.backup),
  (
    name: '匯入 CSV',
    words: ['CSV', '匯入'],
    page: SettingsDestination.importExport,
  ),
  (
    name: '匯出紀錄',
    words: ['匯出', 'Excel'],
    page: SettingsDestination.importExport,
  ),
  (name: '電子發票', words: ['發票', '載具'], page: SettingsDestination.importExport),
  (
    name: '到期提醒',
    words: ['信用卡', '定期', '通知'],
    page: SettingsDestination.reminders,
  ),
  (name: '預算提醒', words: ['預算', '通知'], page: SettingsDestination.reminders),
  (
    name: '每日記帳提醒',
    words: ['每天', '提醒時間', '通知'],
    page: SettingsDestination.reminders,
  ),
  (name: '日曆', words: ['行事曆', '同步'], page: SettingsDestination.reminders),
  (name: '密碼', words: ['變更密碼', '設定密碼'], page: SettingsDestination.security),
  (name: '救援碼', words: ['忘記密碼'], page: SettingsDestination.security),
  (
    name: '生物辨識解鎖',
    // Exception to glossary: search words: 指紋 finds the setting too.
    words: ['指紋', '臉部', '生物辨識'],
    page: SettingsDestination.security,
  ),
  (
    name: LockWords.autoLock,
    words: LockWords.autoLockSearch,
    page: SettingsDestination.security,
  ),
  (name: '禁止截圖', words: ['截圖', '錄影', '隱私'], page: SettingsDestination.security),
  (name: '外觀', words: ['深色', '淺色', '主題'], page: SettingsDestination.appearance),
  (name: '震動', words: ['觸感'], page: SettingsDestination.appearance),
  (name: '桌面小工具', words: ['小工具', '桌面'], page: SettingsDestination.appearance),
  (name: '總覽區塊', words: ['排序', '隱藏'], page: SettingsDestination.appearance),
  (
    name: BrokerDiscountText.title,
    words: BrokerDiscountText.searchWords,
    page: SettingsDestination.appearance,
  ),
  (
    name: '最近刪除',
    words: [Words.delete, '回收', '放回'],
    page: SettingsDestination.trash,
  ),
  (name: '自動檢查新版本', words: ['更新', '版本'], page: SettingsDestination.about),
  (name: '診斷', words: ['錯誤', '效能'], page: SettingsDestination.about),
];

/// The settings whose name or other words hold [query]; none for a blank
/// query.
List<SettingTopic> findSettings(String query) {
  final words = query.trim().toLowerCase();
  if (words.isEmpty) return const [];
  return [
    for (final topic in settingTopics)
      if ([
        topic.name,
        ...topic.words,
      ].any((w) => w.toLowerCase().contains(words)))
        topic,
  ];
}

/// A search box above the settings' first page: typing shows the
/// settings found, each opening its page; cleared, the page is back.
class SettingsSearch extends StatefulWidget {
  const SettingsSearch({super.key, required this.child, required this.onOpen});

  /// The first page, shown while nothing is typed.
  final List<Widget> child;
  final ValueChanged<SettingsDestination> onOpen;

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
    final found = findSettings(_text.text);
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
                  _Found(topic, onTap: () => widget.onOpen(topic.page)),
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

  final SettingTopic topic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TapArea(
    label: '${topic.name}，在${topic.page.label}',
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
              topic.name,
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
