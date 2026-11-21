import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

/// What the app's rules look for in its syntax tree, shared by the rules
/// (test/app_syntax_test.dart) and the status report (bin/status.dart).

/// Every library under the app's lib, by its path from there.
Map<String, CompilationUnit> appUnits(String root) {
  final lib = p.join(root, 'apps', 'expense_tracker', 'lib');
  return {
    for (final f in Directory(lib).listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart'))
        p.relative(f.path, from: lib).replaceAll(r'\', '/'): parseString(
          content: f.readAsStringSync(),
          path: f.path,
          throwIfDiagnostics: false,
        ).unit,
  };
}

/// The screens and models that take the whole ledger.
List<String> wholeLedgerFiles(Map<String, CompilationUnit> units) => [
  for (final MapEntry(key: path, value: unit) in units.entries)
    if (path.startsWith('src/features/') || path.startsWith('src/app/'))
      if (LedgerUses().run(unit).isNotEmpty) path,
];

/// Walks a unit and keeps a line for each thing it is looking for.
abstract class Finder extends RecursiveAstVisitor<void> {
  final found = <String>[];

  List<String> run(CompilationUnit unit) {
    unit.accept(this);
    return found;
  }

  void keep(AstNode node) {
    final unit = node.root as CompilationUnit;
    final line = unit.lineInfo.getLocation(node.offset).lineNumber;
    found.add('line $line: ${node.toSource()}');
  }
}

/// `Color(0x…)` or `Shade(0x…)`, with or without `const`.
final class ColourLiterals extends Finder {
  static const _names = {'Color', 'Shade'};

  bool _isColour(String name, ArgumentList args) =>
      _names.contains(name) &&
      args.arguments.isNotEmpty &&
      args.arguments.first is IntegerLiteral;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (_isColour(node.constructorName.type.name.lexeme, node.argumentList)) {
      keep(node);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null &&
        _isColour(node.methodName.name, node.argumentList)) {
      keep(node);
    }
    super.visitMethodInvocation(node);
  }
}

/// `fontSize:` given a number, or a choice with a number on either side.
final class FontSizeLiterals extends Finder {
  static bool _number(Expression e) => switch (e) {
    IntegerLiteral() || DoubleLiteral() => true,
    ParenthesizedExpression(:final expression) => _number(expression),
    ConditionalExpression(:final thenExpression, :final elseExpression) =>
      _number(thenExpression) || _number(elseExpression),
    _ => false,
  };

  @override
  void visitNamedArgument(NamedArgument node) {
    if (node.name.lexeme == 'fontSize' && _number(node.argumentExpression)) {
      keep(node);
    }
    super.visitNamedArgument(node);
  }
}

/// `x as Map`, `as String` and the like: a cast to a plain type.
final class Casts extends Finder {
  static const _plain = {
    'Map',
    'List',
    'String',
    'num',
    'int',
    'bool',
    'double',
    'Object',
  };

  @override
  void visitAsExpression(AsExpression node) {
    final type = node.type;
    if (type is NamedType && _plain.contains(type.name.lexeme)) keep(node);
    super.visitAsExpression(node);
  }
}

/// Any use of the name `Ledger` in code: a type, a call or a value.
final class LedgerUses extends Finder {
  @override
  void visitNamedType(NamedType node) {
    if (node.name.lexeme == 'Ledger') keep(node);
    super.visitNamedType(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == 'Ledger') keep(node);
    super.visitSimpleIdentifier(node);
  }
}
