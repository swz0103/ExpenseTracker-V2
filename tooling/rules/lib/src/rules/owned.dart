import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../config.dart';
import '../engine.dart';
import 'calls.dart';

/// Whether [file] is code (not a test) the owned-value rules look at.
bool _isCode(SourceFile file) =>
    file.isUnder(appLib) ||
    (file.path.startsWith('packages/') || file.isUnder(infrastructureDir)) &&
        file.path.contains('/lib/');

/// B4: days and months are worked out by core's calendar helpers
/// (`dayOf`, `monthStart`, `monthEnd`, `monthStarts`, `monthIndex`,
/// `shiftMonth`, `monthsAfter`, `yearBefore`), not by hand around
/// `DateTime.utc`. A month or year step that keeps a day,
/// `DateTime.utc(y, m - 1, d)` or `DateTime.utc(y + 1, m, d)`, runs over
/// into the next month when that month is shorter (31 March one month
/// back is 3 March); only day 1, which every month has, is let pass.
///
/// Known noise: `DateTime.utc(a, b - c)` that is not a month step, and a
/// product with 12 that names a year but is not a month count, are
/// flagged all the same; a step written through variables is missed, and
/// so is a year stepped by anything but a written number.
final class CalendarByHand extends FileRule {
  const CalendarByHand();

  @override
  String get id => 'B4-calendar-by-hand';

  @override
  String get purpose =>
      'a day, month end, month step or month count worked out by hand';

  @override
  bool appliesTo(SourceFile file) =>
      _isCode(file) && !file.isUnderAny(calendarOwners);

  @override
  List<Violation> checkFile(SourceFile file) {
    final found = <Violation>[];
    void flag(AstNode node, String message) =>
        found.add(Violation(id, file.path, file.lineOfNode(node), message));
    for (final call in callsIn(file)) {
      if (!call.matches('DateTime', 'utc')) continue;
      final args = call.arguments;
      if (args.length == 3 && _isDayStrip(args)) {
        flag(call.node, 'a day stripped by hand: use dayOf');
      } else if (args.length == 3 &&
          args[2] is IntegerLiteral &&
          (args[2] as IntegerLiteral).value == 0) {
        flag(call.node, 'a month end by hand: use monthEnd or daysInMonth');
      } else if (args.length == 2 && _isStep(args[1])) {
        flag(
          call.node,
          'a month stepped by hand: use monthStart or shiftMonth',
        );
      } else if (args.length == 3 &&
          (_isStep(args[0], byNumber: true) || _isStep(args[1])) &&
          !(args[2] is IntegerLiteral &&
              (args[2] as IntegerLiteral).value == 1)) {
        flag(
          call.node,
          'a month or year stepped by hand with its day: use monthsAfter '
          'or yearBefore',
        );
      }
    }
    final products = _Products();
    file.unit.accept(products);
    for (final node in products.found) {
      flag(node, 'months counted by hand: use monthIndex');
    }
    return found;
  }

  /// `a + n` or `a - n`: a month stepped; a year only [byNumber], a
  /// written number of years (`year - 1`), so that a year brought to
  /// another calendar (`rocYear + rocYearOffset`) passes.
  static bool _isStep(Argument e, {bool byNumber = false}) =>
      e is BinaryExpression &&
      const {'+', '-'}.contains(e.operator.lexeme) &&
      (!byNumber || e.rightOperand is IntegerLiteral);

  /// `DateTime.utc(x.year, x.month, x.day)` of one and the same `x`.
  static bool _isDayStrip(NodeList<Argument> args) {
    String? targetOf(Argument a, String field) => switch (a) {
      PrefixedIdentifier(:final prefix, :final identifier)
          when identifier.name == field =>
        prefix.name,
      PropertyAccess(:final target?, :final propertyName)
          when propertyName.name == field =>
        target.toSource(),
      _ => null,
    };
    final year = targetOf(args[0], 'year');
    return year != null &&
        targetOf(args[1], 'month') == year &&
        targetOf(args[2], 'day') == year;
  }
}

/// Products of 12 with something that names a year: `year * 12`.
final class _Products extends RecursiveAstVisitor<void> {
  final found = <BinaryExpression>[];

  @override
  void visitBinaryExpression(BinaryExpression node) {
    if (node.operator.lexeme == '*') {
      final (l, r) = (node.leftOperand, node.rightOperand);
      bool twelve(Expression e) => e is IntegerLiteral && e.value == 12;
      bool year(Expression e) => e.toSource().contains('year');
      if (twelve(l) && year(r) || twelve(r) && year(l)) found.add(node);
    }
    super.visitBinaryExpression(node);
  }
}

/// B5: a value with one owner is written only there: the font stack's
/// family, the build-number define, the last calendar year
/// ([ownedValues]).
///
/// Known noise: the same string or number used for something unrelated
/// is flagged all the same.
final class OwnedValues extends FileRule {
  const OwnedValues();

  @override
  String get id => 'B5-owned-values';

  @override
  String get purpose => 'a value with one owner is written outside it';

  @override
  bool appliesTo(SourceFile file) => _isCode(file);

  @override
  List<Violation> checkFile(SourceFile file) {
    final literals = _Literals();
    file.unit.accept(literals);
    return [
      for (final (node, value) in literals.found)
        if (ownedValues[value] case final owners?)
          if (!file.isUnderAny(owners))
            Violation(
              id,
              file.path,
              file.lineOfNode(node),
              '$value is written outside ${owners.join(', ')}',
            ),
    ];
  }
}

final class _Literals extends RecursiveAstVisitor<void> {
  final found = <(AstNode, Object)>[];

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    found.add((node, node.value));
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitIntegerLiteral(IntegerLiteral node) {
    final value = node.value;
    if (value != null) found.add((node, value));
    super.visitIntegerLiteral(node);
  }
}
