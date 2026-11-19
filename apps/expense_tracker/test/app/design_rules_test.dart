import 'dart:math';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'layout.dart';
import 'rule_exceptions.dart';

/// The design system's rules, as docs/design.md sets them out: colours,
/// sizes of words and buttons come from core/design_system, never written in a
/// page, so one change there reaches every page and both themes.
void main() {
  final files = [
    for (final f in Directory(Layout.src).listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart')) f,
  ];
  String path(File f) => f.uri.path;
  bool under(File f, List<String> places) =>
      places.any((p) => path(f).contains(p));

  test('colours are named in core/design_system, not written in a page', () {
    // A category's colour is data, kept with the ledger and made up for
    // the preview; the look names every other colour.
    final literal = RegExp(r'(Color|Shade)\(0x');
    for (final f in files) {
      if (under(f, Layout.colourLiteralExempt)) continue;
      expect(
        literal.hasMatch(f.readAsStringSync()),
        isFalse,
        reason: '${path(f)}: name the colour in ${Layout.themeFile}',
      );
    }
  });

  test('words take a size from the type scale', () {
    // Also a size picked between two, as `fontSize: done ? 16 : 15`;
    // a size worked out from another, as `size * 0.44`, may stand.
    final literal = RegExp(r'fontSize: (\d|[^,\n]*[?:] *\d+(\.\d+)? *[,:])');
    for (final f in files) {
      if (path(f).endsWith(Layout.typeFile)) continue;
      expect(
        literal.hasMatch(f.readAsStringSync()),
        isFalse,
        reason: '${path(f)}: use TextSize from core/design_system/type.dart',
      );
    }
  });

  test('words said in many places come from Words', () {
    // One word, one place: '收入' written on a page drifts from the
    // '收入' written on the next. Data that must keep its spelling
    // whatever the screens say, such as a CSV's columns or a category's
    // name, is marked `Exception to shared words`.
    final source = File('lib/src/core/formatting/words.dart')
        .readAsStringSync();
    final words = [
      for (final m in RegExp(
        r"static const \w+ = '([^']+)';",
      ).allMatches(source))
        m.group(1)!,
    ];
    expect(words, isNotEmpty);
    final faults = <String>[];
    for (final f in files) {
      final name = path(f);
      if (name.endsWith('core/formatting/words.dart') ||
          name.contains('/demo/')) {
        continue;
      }
      final lines = f.readAsLinesSync();
      if (excusedFile(lines, 'shared words')) continue;
      for (final (i, line) in lines.indexed) {
        for (final word in words) {
          if (!line.contains("'$word'")) continue;
          if (excusedAt(lines, i, 'shared words')) continue;
          faults.add('$name:${i + 1}: say \'$word\' with Words');
        }
      }
    }
    expect(faults, isEmpty, reason: faults.join('\n'));
  });

  test('how much larger the phone draws words is asked in one place', () {
    // Worked out on each page, with a different size each time, it gave
    // a different answer for Android's own 200%, which is not linear.
    for (final f in files) {
      if (path(f).endsWith(Layout.typeFile)) continue;
      expect(
        f.readAsStringSync().contains('textScalerOf('),
        isFalse,
        reason: '${path(f)}: use textGrowth or wordsWidth from type.dart',
      );
    }
  });

  test('buttons take their look from core/design_system', () {
    final own = RegExp(r'(Filled|Text)Button\.styleFrom\(');
    for (final f in files) {
      if (under(f, [Layout.designSystemDir])) continue;
      expect(
        own.hasMatch(f.readAsStringSync()),
        isFalse,
        reason: '${path(f)}: use solidButton or wordButton',
      );
    }
  });

  test('pages use the colour blocks, not the retired white cards', () {
    // ADR-0006: these were replaced by FigureCard, HeroFigure,
    // FigureCells, CardRow, GroupBox, SectionTitle, FormGroup, SquareIcon
    // and RoundIcon; white cards with a shadow went with them.
    final retired = RegExp(
      r'\b(Tile|TileRow|TileStats|SoftPanel|FormBlock|SectionHead|IconChip|'
      r'IconBadge|MenuPanel|MenuRow|PairBars)\(|Hue\.(card|tile)Shadow',
    );
    for (final f in files) {
      if (under(f, [Layout.designSystemDir])) continue;
      final match = retired.firstMatch(f.readAsStringSync());
      expect(
        match,
        isNull,
        reason: '${path(f)}: ${match?[0]} is retired (docs/design.md)',
      );
    }
  });

  test(
    'dates are written by core/formatting/dates.dart, not built by hand',
    () {
      final handBuilt = RegExp(
        r'\.(month|year)\}/\$\{|\.month\} 月 \$\{|\.year\} 年 \$\{|'
        r'週\$\{weekdayNames\[\w+\.weekday',
      );
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        if (file.path.endsWith('core/formatting/dates.dart')) continue;
        final lines = file.readAsLinesSync();
        for (final (i, line) in lines.indexed) {
          expect(
            handBuilt.hasMatch(line),
            isFalse,
            reason: '${file.path}:${i + 1} builds a date: use dates.dart',
          );
        }
      }
    },
  );

  test('corners and gaps take a step from Radii and Space', () {
    // A fraction is a fine adjustment below the grid, and corners past
    // 48 belong to one drawing; whole numbers otherwise are steps.
    final radius = RegExp(r'Radius\.circular\((\d+)\)');
    final named = RegExp(r'\bradius: \d');
    final insets = RegExp(r'EdgeInsets\.\w+\(([^()]*)\)');
    final whole = RegExp(r'(?<![\w.])(\d+)(?![\w.])');
    final gap = RegExp(r'SizedBox\((?:height|width): (\d+)(?![\w.])');
    const own = [
      'core/design_system/shape.dart',
      'core/design_system/spacing.dart',
    ];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (own.any(file.path.endsWith)) continue;
      final lines = file.readAsLinesSync();
      for (final (i, line) in lines.indexed) {
        final at = '${file.path}:${i + 1}';
        // A widget's own radius too, but for a splash's reach, which is
        // no corner, and a file marked `Exception to the radius scale`.
        if (named.hasMatch(line) &&
            !excusedFile(lines, 'the radius scale') &&
            !lines
                .sublist(max(0, i - 8), i + 1)
                .any((l) => l.contains('InkResponse('))) {
          fail('$at: use Radii for radius:');
        }
        for (final m in radius.allMatches(line)) {
          expect(int.parse(m[1]!), greaterThan(48), reason: '$at: use Radii');
        }
        for (final m in insets.allMatches(line)) {
          for (final n in whole.allMatches(m[1]!)) {
            expect(n[1], '0', reason: '$at: use Space');
          }
        }
        for (final m in gap.allMatches(line)) {
          expect(int.parse(m[1]!), greaterThan(24), reason: '$at: use Space');
        }
      }
    }
  });

  test('every animation stops when the person asks to reduce motion', () {
    // A duration goes through Motion.of, which is none while motion is
    // off, or is marked `Exception to motion` with how it is spared.
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (file.path.endsWith('core/design_system/motion.dart')) continue;
      final lines = file.readAsLinesSync();
      for (final (i, line) in lines.indexed) {
        // Given no time, AnimatedSize trips over its own layout.
        expect(
          line.contains('AnimatedSize('),
          isFalse,
          reason: '${file.path}:${i + 1}: use MotionSize',
        );
        if (!line.contains('duration:') || line.trimLeft().startsWith('//')) {
          continue;
        }
        if (line.contains('Motion.of(') || line.contains('Duration.zero')) {
          continue;
        }
        // MotionSize leaves its animation out while motion is off.
        if (lines
            .sublist(max(0, i - 3), i)
            .any((l) => l.contains('MotionSize('))) {
          continue;
        }
        expect(
          excusedAt(lines, i, 'motion'),
          isTrue,
          reason: '${file.path}:${i + 1}: use Motion.of(context, …)',
        );
      }
    }
  });

  test('animations keep to the motion scale', () {
    // Motion's durations (Material 3's), or a mark of why not; a Timer
    // is a wait, not a movement.
    final literal = RegExp(r'Duration\(\s*milliseconds:');
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (file.path.endsWith('core/design_system/motion.dart')) continue;
      final text = file.readAsStringSync();
      final lines = text.split('\n');
      for (final m in literal.allMatches(text)) {
        final i = '\n'.allMatches(text.substring(0, m.start)).length;
        if (lines[i].contains('Timer(')) continue;
        expect(
          excusedAt(lines, i, 'the motion scale'),
          isTrue,
          reason: '${file.path}:${i + 1}: use one of Motion\'s durations',
        );
      }
    }
  });
}
