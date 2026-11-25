import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:architecture_checks/app_syntax.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The design system's rules (docs/design.md) read from the syntax tree:
/// buttons, retired widgets, word sizes, corners and gaps, motion and
/// shared words. A comment or a string never trips them, and another way
/// of writing the same call does not slip past. Exceptions are marked in
/// place: `// Exception to <rule>: <why>`.
void main() {
  final root = p.normalize(p.join(Directory.current.path, '..', '..'));
  final sources = appSources(root);
  const designSystem = 'src/core/design_system/';

  List<String> where(
    bool Function(AppSource s) applies,
    Iterable<String> Function(AppSource s) faults,
  ) => [
    for (final s in sources)
      if (applies(s)) ...faults(s),
  ];

  test('buttons take their look from core/design_system', () {
    const buttons = {
      'FilledButton',
      'TextButton',
      'OutlinedButton',
      'ElevatedButton',
    };
    final faults = where((s) => !s.path.startsWith(designSystem), (s) sync* {
      for (final call in Calls.of(s.unit)) {
        final (type, member, _) = callOf(call)!;
        if (buttons.contains(type) && member == 'styleFrom') {
          yield '${s.path}:${s.lineOf(call)}: use solidButton or wordButton';
        }
      }
    });
    expect(faults, isEmpty, reason: faults.join('\n'));
  });

  test('pages use the colour blocks, not the retired white cards', () {
    // Replaced by FigureCard, HeroFigure, FigureCells, CardRow, GroupBox,
    // SectionTitle, FormGroup, SquareIcon and RoundIcon.
    const retired = {
      'Tile',
      'TileRow',
      'TileStats',
      'SoftPanel',
      'FormBlock',
      'SectionHead',
      'IconChip',
      'IconBadge',
      'MenuPanel',
      'MenuRow',
      'PairBars',
    };
    final faults = where((s) => !s.path.startsWith(designSystem), (s) sync* {
      for (final call in Calls.of(s.unit)) {
        if (retired.contains(callOf(call)!.$1)) {
          yield '${s.path}:${s.lineOf(call)}: retired (docs/design.md)';
        }
      }
      for (final m in RegExp(
        r'AppColors\.(card|tile)Shadow',
      ).allMatches(s.unit.toSource())) {
        yield '${s.path}: ${m[0]} is retired';
      }
    });
    expect(faults, isEmpty, reason: faults.join('\n'));
  });

  test('panels that ask or tell come from the design system (WP-E)', () {
    // One look for every question, notice and choice: confirm, askText,
    // tell, chooseOne, pickTime, pickDateRange, a DialogBlock or a
    // DialogFrame from core/design_system, opened by its showPanel or
    // showSheet; never a dialog, sheet, picker or menu of a screen's own.
    // Every reference counts, a tear-off (`builder: AlertDialog.new`) as
    // much as a call (review 39 #5).
    const raw = {
      'AlertDialog',
      'SimpleDialog',
      'Dialog',
      'CupertinoAlertDialog',
      'showDialog',
      'showAdaptiveDialog',
      'showGeneralDialog',
      'showCupertinoDialog',
      'showModalBottomSheet',
      'showBottomSheet',
      'showCupertinoModalPopup',
      'CupertinoActionSheet',
      'showDatePicker',
      'showTimePicker',
      'showDateRangePicker',
      'DatePickerDialog',
      'TimePickerDialog',
      'DateRangePickerDialog',
      'showAboutDialog',
      'AboutDialog',
      'showMenu',
    };
    final faults = where((s) => !s.path.startsWith(designSystem), (s) sync* {
      for (final (name, node) in _Names.of(s.unit)) {
        if (raw.contains(name)) {
          yield '${s.path}:${s.lineOf(node)}: $name; use confirm, askText, '
              'tell, chooseOne or DialogBlock (core/design_system)';
        }
      }
    });
    expect(faults, isEmpty, reason: faults.join('\n'));
  });

  test('the panel rule sees a tear-off and a sheet, not a word in a '
      'comment or a string (review 39 #5)', () {
    final unit = AppSource('x.dart', '''
// showModalBottomSheet in a comment
final a = 'showMenu';
final b = Builder(builder: AlertDialog.new);
void c(BuildContext context) => showModalBottomSheet(context: context);
Widget d() => CupertinoActionSheet();
''').unit;
    expect(
      [for (final (name, _) in _Names.of(unit)) name],
      containsAll([
        'AlertDialog',
        'showModalBottomSheet',
        'CupertinoActionSheet',
      ]),
    );
    expect([
      for (final (name, _) in _Names.of(unit)) name,
    ], isNot(contains('showMenu')));
  });

  test('how much larger the phone draws words is asked in one place', () {
    // Worked out on each page it gave a different answer for Android's
    // own 200%, which is not linear.
    final faults = where((s) => !s.path.endsWith('design_system/type.dart'), (
      s,
    ) sync* {
      for (final call in Calls.of(s.unit)) {
        final (type, member, _) = callOf(call)!;
        if (type == 'textScalerOf' || member == 'textScalerOf') {
          yield '${s.path}:${s.lineOf(call)}: use textGrowth or wordsWidth';
        }
      }
    });
    expect(faults, isEmpty, reason: faults.join('\n'));
  });

  test('corners and gaps take a step from Radii and Space', () {
    // A fraction is a fine adjustment below the grid, and corners past 48
    // belong to one drawing; whole numbers otherwise are steps.
    final faults = where(
      (s) =>
          !s.path.endsWith('design_system/shape.dart') &&
          !s.path.endsWith('design_system/spacing.dart'),
      (s) sync* {
        String at(AstNode n) => '${s.path}:${s.lineOf(n)}';
        for (final call in Calls.of(s.unit)) {
          final (type, member, args) = callOf(call)!;
          final values = [for (final a in args.arguments) a.argumentExpression];
          if (type == 'Radius' && member == 'circular') {
            final n = wholeLiteral(values.first);
            if (n != null && n <= 48) yield '${at(call)}: use Radii';
          }
          if (type == 'EdgeInsets' || type == 'EdgeInsetsDirectional') {
            for (final v in values) {
              final n = wholeLiteral(v);
              if (n != null && n != 0) yield '${at(call)}: use Space';
            }
          }
          // A gap is a SizedBox with nothing in it; one holding a child is
          // that child's size, not a gap.
          final gap = !args.arguments.any(
            (a) => a is NamedArgument && a.name.lexeme == 'child',
          );
          if (type == 'SizedBox' && member == null && gap) {
            for (final a in args.arguments) {
              if (a is! NamedArgument) continue;
              if (a.name.lexeme != 'height' && a.name.lexeme != 'width') {
                continue;
              }
              final n = wholeLiteral(a.argumentExpression);
              if (n != null && n <= 24) yield '${at(call)}: use Space';
            }
          }
        }
        // A widget's own radius too, but for a splash's reach, which is no
        // corner, and a file marked `Exception to the radius scale`.
        if (!s.excusedFile('the radius scale')) {
          for (final a in NamedArguments.of(s.unit)) {
            if (a.name.lexeme != 'radius') continue;
            final e = a.argumentExpression;
            if (e is! IntegerLiteral && e is! DoubleLiteral) continue;
            if (insideCall(a, 'InkResponse')) continue;
            yield '${at(a)}: use Radii for radius:';
          }
        }
      },
    );
    expect(faults, isEmpty, reason: faults.join('\n'));
  });

  test('every animation stops when the person asks to reduce motion', () {
    // A duration goes through Motion.of, which is none while motion is
    // off, or is marked `Exception to motion` with how it is spared.
    final faults = where((s) => !s.path.endsWith('design_system/motion.dart'), (
      s,
    ) sync* {
      for (final call in Calls.of(s.unit)) {
        // Given no time, AnimatedSize trips over its own layout.
        if (callOf(call)!.$1 == 'AnimatedSize') {
          yield '${s.path}:${s.lineOf(call)}: use MotionSize';
        }
      }
      for (final a in NamedArguments.of(s.unit)) {
        if (a.name.lexeme != 'duration') continue;
        final e = a.argumentExpression;
        final viaMotion =
            e is MethodInvocation &&
            e.methodName.name == 'of' &&
            e.target?.toSource() == 'Motion';
        final none = e.toSource() == 'Duration.zero';
        if (viaMotion || none || insideCall(a, 'MotionSize')) continue;
        if (s.excusedAt(s.lineOf(a), 'motion')) continue;
        yield '${s.path}:${s.lineOf(a)}: use Motion.of(context, …)';
      }
    });
    expect(faults, isEmpty, reason: faults.join('\n'));
  });

  test('animations keep to the motion scale', () {
    // Motion's durations (Material 3's), or a mark of why not; a Timer is
    // a wait, not a movement.
    final faults = where((s) => !s.path.endsWith('design_system/motion.dart'), (
      s,
    ) sync* {
      for (final call in Calls.of(s.unit)) {
        final (type, member, args) = callOf(call)!;
        if (type != 'Duration' || member != null) continue;
        final millis = args.arguments.any(
          (a) => a is NamedArgument && a.name.lexeme == 'milliseconds',
        );
        if (!millis || insideCall(call, 'Timer')) continue;
        if (s.excusedAt(s.lineOf(call), 'the motion scale')) continue;
        yield '${s.path}:${s.lineOf(call)}: use one of Motion\'s durations';
      }
    });
    expect(faults, isEmpty, reason: faults.join('\n'));
  });

  test('words said in many places come from Words', () {
    // One word, one place: '收入' written on a page drifts from the '收入'
    // on the next. Data that keeps its spelling whatever the screens say,
    // such as a CSV's columns, is marked `Exception to shared words`.
    final words = {
      for (final s in sources)
        if (s.path.endsWith('core/formatting/words.dart'))
          for (final literal in Strings.of(s.unit)) literal.value,
    };
    expect(words, isNotEmpty);
    final faults = where(
      (s) =>
          !s.path.endsWith('core/formatting/words.dart') &&
          !s.path.contains('/demo/') &&
          !s.excusedFile('shared words'),
      (s) sync* {
        for (final literal in Strings.of(s.unit)) {
          if (!words.contains(literal.value)) continue;
          if (s.excusedAt(s.lineOf(literal), 'shared words')) continue;
          yield '${s.path}:${s.lineOf(literal)}: say '
              "'${literal.value}' with Words";
        }
      },
    );
    expect(faults, isEmpty, reason: faults.join('\n'));
  });
}

/// Every name a unit refers to: identifiers and types, each with where it
/// is; never a word in a comment or a string.
final class _Names extends RecursiveAstVisitor<void> {
  final found = <(String, AstNode)>[];

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    found.add((node.name, node));
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    found.add((node.name.lexeme, node));
    super.visitNamedType(node);
  }

  static List<(String, AstNode)> of(CompilationUnit unit) =>
      (_Names()..visitCompilationUnit(unit)).found;
}
