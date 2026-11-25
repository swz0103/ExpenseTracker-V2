import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/rule_exceptions.dart';

/// D81's glossary: one word for one thing in everything the person reads,
/// the message catalogues (core/messages) and the words still written in
/// place. Each variant below has the word to use instead. Words whose
/// choice depends on what is meant — 恢復 (archived), 復原 (just deleted,
/// the trash) and 還原 (from a backup) — are not told apart by a test.
///
/// A string that rightly uses a variant, such as a search word or the
/// heading of a file format kept for older files, carries
/// `// Exception to glossary: <why>` on its line or just above it
/// (rule_exceptions.dart).
const _variants = <String, String>{
  '移除': '刪除 (D81)',
  '指紋': '生物辨識 (D56)',
  '(?<!新)台幣': '新台幣',
  '臺幣': '新台幣',
  '股利': '股息',
  '保存': '儲存',
  '(?<!暫)存檔': '儲存',
  '啟用': '開啟 (a switch) or 打開 (the book, the app)',
  '開啟(?=帳本|記帳本|\\s?App|診斷)': '打開 (the book, the app)',
  '無法開啟(?!相機)': '無法打開',
  '點此開啟': '點此打開',
  '排定|預約': '預定 (an entry dated later)',
  '還卡費|付卡費': '繳卡費',
  '繳費日': '繳款日',
  '記錄': '紀錄 (the noun; 記 to write one)',
  // A number and its unit have a space between (D81).
  '\\d折': 'a space between the number and 折, as 6 折',
};

/// The Chinese strings of a line: single- or double-quoted, as written.
final _literal = RegExp(
  r"'(?:[^'\\]|\\.)*'"
  '|'
  r'"(?:[^"\\]|\\.)*"',
);

/// The variants of [lines], each as `line: word → instead`, from 1.
List<String> variantsIn(List<String> lines) {
  final found = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trimLeft().startsWith('//')) continue;
    for (final m in _literal.allMatches(line)) {
      for (final MapEntry(key: variant, value: instead) in _variants.entries) {
        final hit = RegExp(variant).firstMatch(m[0]!);
        if (hit == null || excusedAt(lines, i, 'glossary')) continue;
        found.add('${i + 1}: ${hit[0]} → $instead');
      }
    }
  }
  return found;
}

/// A run of string literals with only white space between, as Dart joins
/// them into one string.
final _joined = RegExp("(?:(?:${_literal.pattern})\\s*)+");

/// D81: a sentence of its own carries no 。, and several in one string end
/// each with it (a question ends with its ？). The strings of [source]
/// that break this, each as `line: string`, from 1; a string continued on
/// the next line is read as one.
List<String> sentenceEndsIn(String source) {
  final lines = source.split('\n');
  final code = [
    for (final line in lines) line.trimLeft().startsWith('//') ? '' : line,
  ].join('\n');
  final found = <String>[];
  for (final run in _joined.allMatches(code)) {
    final text = _literal
        .allMatches(run[0]!)
        .map((m) => m[0]!.substring(1, m[0]!.length - 1))
        .join()
        // A sentence endSentence closes ends there.
        .replaceAll(RegExp(r'\$\{endSentence\([^}]*\)\}'), '。');
    final single =
        text.endsWith('。') &&
        !text.substring(0, text.length - 1).contains(RegExp('[。？！]'));
    if (!single && !text.contains('。。')) continue;
    final line = '\n'.allMatches(code.substring(0, run.start)).length;
    if (excusedAt(lines, line, 'sentence ends')) continue;
    found.add('${line + 1}: $text');
  }
  return found;
}

/// Files the rule leaves to another work package for now, with why.
const _elsewhere = <String>{};

void main() {
  test('the finder sees variants in strings, not in comments', () {
    expect(variantsIn(["  label: '移除收據',"]), ['1: 移除 → 刪除 (D81)']);
    expect(variantsIn(["  // 移除 in a comment"]), isEmpty);
    expect(variantsIn(["  label: '折合新台幣',"]), isEmpty);
    expect(variantsIn(["  label: '折合台幣',"]), ['1: 台幣 → 新台幣']);
    expect(variantsIn(["  t: '例如 6 折',"]), isEmpty);
    expect(variantsIn(["  t: '例如 6折',"]), [
      '1: 6折 → a space between the number and 折, as 6 折',
    ]);
    expect(variantsIn(["  t: '無法開啟相機',"]), isEmpty);
    expect(
      variantsIn([
        '  // Exception to glossary: a search word.',
        "  words: ['指紋'],",
      ]),
      isEmpty,
    );
  });

  test('the sentence-end finder reads a string as Dart joins it', () {
    expect(sentenceEndsIn("  a = '請稍候再試。';"), ['1: 請稍候再試。']);
    expect(sentenceEndsIn("  a = '請稍候再試';"), isEmpty);
    expect(sentenceEndsIn("  a = '沒有復原。它們留著。';"), isEmpty);
    expect(sentenceEndsIn("  a = '要還原嗎？會先備份。';"), isEmpty);
    expect(sentenceEndsIn("  a = '已記下。。';"), ['1: 已記下。。']);
    expect(sentenceEndsIn(r"  a = '${endSentence(x)}還沒有升級。';"), isEmpty);
    expect(sentenceEndsIn("  a = '第一句，'\n      '還是同一句。';"), ['1: 第一句，還是同一句。']);
    expect(sentenceEndsIn("  a = '第一句。'\n      '第二句。';"), isEmpty);
    expect(sentenceEndsIn("  // '在註解裡。'"), isEmpty);
    expect(
      sentenceEndsIn("  // Exception to sentence ends: a quote.\n  a = '照抄。';"),
      isEmpty,
    );
  });

  test('what the person reads ends sentences by one rule: the message '
      'catalogues and the words still in place (D81, reviews 31 and 32)', () {
    final found = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      for (final hit in sentenceEndsIn(f.readAsStringSync())) {
        found.add('${f.path}:$hit');
      }
    }
    if (found.isNotEmpty) {
      fail(
        'A sentence of its own ends without 。, several each with it '
        '(D81):\n${found.join('\n')}',
      );
    }
  });

  test('what the person reads uses one word for one thing (D81)', () {
    final found = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (_elsewhere.contains(f.path)) continue;
      for (final hit in variantsIn(f.readAsLinesSync())) {
        found.add('${f.path}:$hit');
      }
    }
    if (found.isNotEmpty) {
      fail(
        'Use the glossary word (D81), or mark a rightful use with '
        '`// Exception to glossary: <why>`:\n${found.join('\n')}',
      );
    }
  });
}
