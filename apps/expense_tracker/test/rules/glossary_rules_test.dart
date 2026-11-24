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

/// Files the rule leaves to another work package for now, with why.
const _elsewhere = {
  // Its one variant is a diagnostics step name ('開啟帳本'), in the open
  // path package 2.0 is rewriting; it changes with that rewrite.
  'lib/src/core/ledger/persistence/sql_ledger_data_source.dart',
};

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
