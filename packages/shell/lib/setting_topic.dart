import 'package:core/money/typed_text.dart';

/// A setting as search finds it: its [name], as the list of settings
/// found shows it, and other [words] a person may type for it. Each is
/// declared beside the card it marks, where that card is built (N8): a
/// setting added without one is caught by settings_search_rules_test.
final class SettingTopic {
  const SettingTopic(this.name, {this.words = const []});

  final String name;
  final List<String> words;

  /// Whether [query] is part of the name or of one of the words, each
  /// read through [searchKey]: 臺 as 台, full-width as half-width, any
  /// case, spaces left out. Never for a blank query.
  bool matches(String query) {
    final key = searchKey(query);
    if (key.isEmpty) return false;
    return [name, ...words].any((w) => searchKey(w).contains(key));
  }

  /// What a screen reader says as the page opens on it.
  String get foundSaid => '已找到「$name」';

  @override
  String toString() => 'SettingTopic($name)';
}
