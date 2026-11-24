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
/// `DateTime.utc` or `DateTime` (with or without hours; a local day
/// stripped is the phone's own day, which is not `dayOf`'s). A month or
/// year step that keeps a day, `DateTime.utc(y, m - 1, d)` or
/// `DateTime.utc(y + 1, m, d)`, runs over into the next month when that
/// month is shorter (31 March one month back is 3 March); only day 1,
/// which every month has, is let pass. A step in brackets, or in either
/// branch of a `?:`, is a step all the same (review 28). A local
/// midnight, `DateTime(y, m, d)` or `DateTime(y, m)`, compared as a
/// moment (`isBefore`, `isAfter`, `isAtSameMomentAs`, `compareTo`), by
/// itself or through a local variable it was put in, is a day compared
/// with the ledger's UTC midnights as an instant: a day off east or west
/// of UTC (review 29).
///
/// Known noise: `DateTime.utc(a, b - c)` that is not a month step, and a
/// product with 12 that names a year but is not a month count, are
/// flagged all the same; a step written through variables is missed. A
/// year is stepped by a written number, or by anything from a value
/// named a year (`d.year - n`); one brought to another calendar by a
/// value named an offset (`rocYear + rocYearOffset`) passes. Two local
/// midnights compared with each other are flagged all the same; a local
/// midnight held in a field, or passed on before it is compared, is
/// missed.
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
      final utc = call.matches('DateTime', 'utc');
      if (!utc && !call.matches(null, 'DateTime')) continue;
      final args = call.arguments;
      // A local day of a moment is the phone's own day, which dayOf (in
      // UTC) is not: only its steps and month ends are by hand.
      if (utc && args.length >= 3 && _isDayStrip(args)) {
        flag(call.node, 'a day stripped by hand: use dayOf');
      } else if (args.length >= 3 && _isInt(args[2], 0)) {
        flag(call.node, 'a month end by hand: use monthEnd or daysInMonth');
      } else if (args.length == 2 && _isStep(args[1])) {
        flag(
          call.node,
          'a month stepped by hand: use monthStart or shiftMonth',
        );
      } else if (args.length >= 3 &&
          (_isStep(args[0], year: true) || _isStep(args[1])) &&
          !_isInt(args[2], 1)) {
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
    final compared = _LocalMidnightsCompared();
    file.unit.accept(compared);
    for (final node in compared.found) {
      flag(
        node,
        'a local midnight compared as a moment with the ledger\'s UTC days: '
        'compare dayOf of both',
      );
    }
    return found;
  }

  /// Whether [e], out of its brackets, is the written number [value].
  static bool _isInt(AstNode e, int value) =>
      _bare(e) is IntegerLiteral && (_bare(e) as IntegerLiteral).value == value;

  /// [e] out of any brackets around it.
  static AstNode _bare(AstNode e) =>
      e is ParenthesizedExpression ? _bare(e.expression) : e;

  /// `a + n` or `a - n`, in brackets or in either branch of a `?:`: a
  /// month stepped. A [year] is stepped by a written number
  /// (`year - 1`), or by anything from a value named a year
  /// (`d.year - n`), but not by a value named an offset, so that a year
  /// brought to another calendar (`rocYear + rocYearOffset`) passes.
  static bool _isStep(AstNode e, {bool year = false}) => switch (_bare(e)) {
    ConditionalExpression(:final thenExpression, :final elseExpression) =>
      _isStep(thenExpression, year: year) ||
          _isStep(elseExpression, year: year),
    BinaryExpression(:final operator, :final leftOperand, :final rightOperand)
        when const {'+', '-'}.contains(operator.lexeme) =>
      !year || _yearStep(leftOperand, _bare(rightOperand)),
    _ => false,
  };

  static bool _yearStep(AstNode left, AstNode right) =>
      right is IntegerLiteral ||
      left.toSource().toLowerCase().endsWith('year') &&
          !(right is Identifier &&
              right.toSource().toLowerCase().endsWith('offset'));

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

/// `isBefore`, `isAfter`, `isAtSameMomentAs` or `compareTo` with a local
/// midnight on either side: `DateTime(y, m)` or `DateTime(y, m, d)`
/// written there, or a local variable that one was put in.
final class _LocalMidnightsCompared extends RecursiveAstVisitor<void> {
  final found = <MethodInvocation>[];

  /// Local variables, by name, that hold a local midnight.
  final _held = <String>{};

  static const _comparisons = {
    'isBefore',
    'isAfter',
    'isAtSameMomentAs',
    'compareTo',
  };

  /// `DateTime(y, m)` or `DateTime(y, m, d)`, without hours: a local
  /// midnight. Unresolved, it may be a method invocation or an instance
  /// creation.
  static bool _isLocalMidnight(AstNode? e) {
    if (e is ParenthesizedExpression) return _isLocalMidnight(e.expression);
    final (String? target, String name, int count) = switch (e) {
      MethodInvocation(:final target, :final methodName, :final argumentList) =>
        (target?.toSource(), methodName.name, argumentList.arguments.length),
      InstanceCreationExpression(:final constructorName, :final argumentList) =>
        (
          constructorName.name?.name,
          constructorName.type.name.lexeme,
          argumentList.arguments.length,
        ),
      _ => ('', '', 0),
    };
    return target == null && name == 'DateTime' && count >= 2 && count <= 3;
  }

  bool _isHeld(AstNode? e) =>
      _isLocalMidnight(e) || e is SimpleIdentifier && _held.contains(e.name);

  @override
  void visitVariableDeclarationStatement(VariableDeclarationStatement node) {
    for (final v in node.variables.variables) {
      if (_isLocalMidnight(v.initializer)) _held.add(v.name.lexeme);
    }
    super.visitVariableDeclarationStatement(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final args = node.argumentList.arguments;
    if (_comparisons.contains(node.methodName.name) &&
        args.length == 1 &&
        (_isHeld(node.target) || _isHeld(args.first))) {
      found.add(node);
    }
    super.visitMethodInvocation(node);
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
