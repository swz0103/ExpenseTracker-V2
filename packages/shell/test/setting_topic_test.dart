import 'package:flutter_test/flutter_test.dart';
import 'package:shell/setting_topic.dart';

void main() {
  test('a topic is found by its name or a word, as typed on a phone', () {
    const topic = SettingTopic('臺灣銀行匯率', words: ['外幣', 'FX']);
    expect(topic.matches('台灣'), isTrue); // 臺 read as 台
    expect(topic.matches('ｆｘ'), isTrue); // full-width, any case
    expect(topic.matches('外 幣'), isTrue); // spaces left out
    expect(topic.matches('股票'), isFalse);
    expect(topic.matches('  '), isFalse);
    expect(topic.foundSaid, '已找到「臺灣銀行匯率」');
    expect('$topic', 'SettingTopic(臺灣銀行匯率)');
  });
}
