import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../config.dart';
import '../engine.dart';
import 'calls.dart';

/// B2: numbers are formatted and parsed in one place.
///
/// Known noise: `toStringAsFixed` on a value that is not money (a
/// percentage for a chart axis) is flagged too; a method named
/// `toStringAsFixed` on a user class would be as well; tear-offs such as
/// `.map(int.parse)` are not invocations and are missed.
final class NumberFormat extends FileRule {
  const NumberFormat();

  @override
  String get id => 'B2-number-format';

  @override
  String get purpose => 'the app formats or parses numbers by hand';

  @override
  bool appliesTo(SourceFile file) =>
      file.isUnder(appLib) && !file.isUnderAny(numberFormatOwners);

  static const _formatters = {'toStringAsFixed', 'toStringAsPrecision'};
  static const _parsers = {'parse', 'tryParse'};
  static const _numTypes = {'int', 'double', 'num'};

  @override
  List<Violation> checkFile(SourceFile file) {
    final found = <Violation>[];
    for (final call in callsIn(file)) {
      final node = call.node;
      final String? what;
      if (node is MethodInvocation && _formatters.contains(call.name)) {
        what = '.${call.name}(';
      } else if (_numTypes.contains(call.target) &&
          _parsers.contains(call.name)) {
        what = '${call.target}.${call.name}(';
      } else {
        what = null;
      }
      if (what != null) {
        found.add(
          Violation(
            id,
            file.path,
            file.lineOfNode(node),
            'number handled by hand with $what',
          ),
        );
      }
    }
    return found;
  }
}

/// B3: "now" comes from the clock, and dates and numbers are padded by the
/// formatting layer.
///
/// Known noise: `padLeft(2, '0')` is also used for things that are not
/// dates (a hex byte, a version part) and is flagged all the same.
final class ClockAndPadding extends FileRule {
  const ClockAndPadding();

  @override
  String get id => 'B3-clock';

  @override
  String get purpose =>
      'the app reads DateTime.now() or pads dates by hand outside their owners';

  @override
  bool appliesTo(SourceFile file) => file.isUnder(appLib);

  @override
  List<Violation> checkFile(SourceFile file) {
    final found = <Violation>[];
    final clockOk = file.isUnderAny(clockOwners);
    final paddingOk = file.isUnderAny(paddingOwners);
    for (final call in callsIn(file)) {
      if (!clockOk && isDateTimeNow(call)) {
        found.add(
          Violation(
            id,
            file.path,
            file.lineOfNode(call.node),
            'DateTime.now() outside the clock',
          ),
        );
      }
      if (!paddingOk && call.node is MethodInvocation && _isPad2(call)) {
        found.add(
          Violation(
            id,
            file.path,
            file.lineOfNode(call.node),
            "hand-made padding .padLeft(2, '0')",
          ),
        );
      }
    }
    return found;
  }

  bool _isPad2(Call call) {
    if (call.name != 'padLeft' || call.arguments.length != 2) return false;
    final width = call.arguments[0];
    final fill = call.arguments[1];
    return width is IntegerLiteral &&
        width.value == 2 &&
        fill is SimpleStringLiteral &&
        fill.value == '0';
  }
}

final _cjk = RegExp('[一-鿿]');

/// Whether a string literal [node] has a CJK character in its fixed text.
bool _hasCjk(StringLiteral node) => switch (node) {
  SimpleStringLiteral() => _cjk.hasMatch(node.value),
  StringInterpolation() => node.elements.any(
    (e) => e is InterpolationString && _cjk.hasMatch(e.value),
  ),
  AdjacentStrings() => node.strings.any(_hasCjk),
};

final class _Literals extends RecursiveAstVisitor<void> {
  _Literals(this.file, this.id);

  final SourceFile file;
  final String id;
  final found = <Violation>[];
  var _skipping = 0;

  void _count(StringLiteral node) {
    if (_skipping == 0 && _hasCjk(node)) {
      found.add(
        Violation(
          id,
          file.path,
          file.lineOfNode(node),
          'user-facing text written inline',
        ),
      );
    }
  }

  void _inside(AstNode node, void Function() visit) {
    _skipping++;
    visit();
    _skipping--;
  }

  /// The expressions inside the `${}` of [node], which can hold literals
  /// of their own.
  void _visitInterpolated(StringLiteral node) {
    switch (node) {
      case StringInterpolation():
        for (final e in node.elements) {
          if (e is InterpolationExpression) e.expression.accept(this);
        }
      case AdjacentStrings():
        node.strings.forEach(_visitInterpolated);
      default:
    }
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) => _count(node);

  @override
  void visitStringInterpolation(StringInterpolation node) {
    _count(node);
    _visitInterpolated(node);
  }

  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    _count(node);
    _visitInterpolated(node);
  }

  @override
  void visitAssertStatement(AssertStatement node) =>
      _inside(node, () => super.visitAssertStatement(node));

  @override
  void visitAssertInitializer(AssertInitializer node) =>
      _inside(node, () => super.visitAssertInitializer(node));

  @override
  void visitThrowExpression(ThrowExpression node) {
    final thrown = node.expression;
    final name = switch (thrown) {
      MethodInvocation() => thrown.methodName.name,
      InstanceCreationExpression() => thrown.constructorName.type.name.lexeme,
      _ => '',
    };
    if (name.endsWith('Error')) {
      _inside(node, () => super.visitThrowExpression(node));
    } else {
      super.visitThrowExpression(node);
    }
  }
}

/// B9: user-facing text lives in the message catalogue; a Chinese literal
/// in a feature or the shell is a string that should be there.
///
/// Known noise: Chinese in `debugPrint`, log lines, test seeds or demo
/// data counts; a literal that is a lookup key rather than text counts;
/// strings under `assert`, and `throw`n `...Error`s, are left out because
/// they are programmer messages, not user text.
final class TextLiterals extends FileRule {
  const TextLiterals();

  @override
  String get id => 'B9-text-literals';

  @override
  String get purpose =>
      'user-facing Chinese text written inline in a feature or the shell';

  @override
  bool appliesTo(SourceFile file) =>
      file.isUnderAny(textScopes) && !file.isUnderAny(textOwners);

  @override
  List<Violation> checkFile(SourceFile file) {
    final visitor = _Literals(file, id);
    file.unit.accept(visitor);
    return visitor.found;
  }
}
