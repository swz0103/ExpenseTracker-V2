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

/// A library of the app with its lines, to read exception marks by:
/// `// Exception to <rule>: <why>` on the line, in the comments right
/// above it, or for the whole file among the comments at its top
/// (the app's test/support/rule_exceptions.dart, the same reading).
final class AppSource {
  AppSource(this.path, String text)
    : lines = text.split('\n'),
      unit = parseString(content: text, throwIfDiagnostics: false).unit;

  final String path;
  final List<String> lines;
  final CompilationUnit unit;

  int lineOf(AstNode node) => unit.lineInfo.getLocation(node.offset).lineNumber;

  bool excusedAt(int line, String rule) {
    final mark = 'Exception to $rule:';
    if (lines[line - 1].contains(mark)) return true;
    for (var i = line - 2; i >= 0; i--) {
      final text = lines[i].trimLeft();
      if (!text.startsWith('//')) return false;
      if (text.contains(mark)) return true;
    }
    return false;
  }

  bool excusedFile(String rule) {
    final mark = 'Exception to $rule:';
    for (final line in lines) {
      final text = line.trimLeft();
      if (text.isEmpty || text.startsWith('//')) {
        if (text.contains(mark)) return true;
        continue;
      }
      return false;
    }
    return false;
  }
}

/// Every library under the app's lib, read with its lines.
List<AppSource> appSources(String root) {
  final lib = p.join(root, 'apps', 'expense_tracker', 'lib');
  return [
    for (final f in Directory(lib).listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart'))
        AppSource(
          p.relative(f.path, from: lib).replaceAll(r'\', '/'),
          f.readAsStringSync(),
        ),
  ];
}

/// A call as written, whether the parser read it as a constructor (with
/// `const` or `new`) or as a method (without): `Radius.circular(8)` is
/// ('Radius', 'circular'), `SizedBox(height: 8)` is ('SizedBox', null).
(String, String?, ArgumentList)? callOf(AstNode node) => switch (node) {
  InstanceCreationExpression(:final constructorName, :final argumentList) => (
    constructorName.type.name.lexeme,
    constructorName.name?.name,
    argumentList,
  ),
  MethodInvocation(:final target?, :final methodName, :final argumentList)
      when target is SimpleIdentifier =>
    (target.name, methodName.name, argumentList),
  MethodInvocation(target: null, :final methodName, :final argumentList) => (
    methodName.name,
    null,
    argumentList,
  ),
  _ => null,
};

/// Whether [node] sits inside a call to [type].
bool insideCall(AstNode node, String type) {
  for (AstNode? n = node.parent; n != null; n = n.parent) {
    if (callOf(n)?.$1 == type) return true;
  }
  return false;
}

/// Every call in a unit, with its line.
final class Calls extends RecursiveAstVisitor<void> {
  final found = <AstNode>[];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    found.add(node);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    found.add(node);
    super.visitMethodInvocation(node);
  }

  /// The calls [callOf] can name; a chained call such as `a.b.c()` is
  /// none of the design system's.
  static List<AstNode> of(CompilationUnit unit) => [
    for (final call in (Calls()..run(unit)).found)
      if (callOf(call) != null) call,
  ];

  void run(CompilationUnit unit) => unit.accept(this);
}

/// Every plain string literal in a unit (not one with interpolation).
final class Strings extends RecursiveAstVisitor<void> {
  final found = <SimpleStringLiteral>[];

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) => found.add(node);

  static List<SimpleStringLiteral> of(CompilationUnit unit) =>
      (Strings()..run(unit)).found;

  void run(CompilationUnit unit) => unit.accept(this);
}

/// Every named argument in a unit.
final class NamedArguments extends RecursiveAstVisitor<void> {
  final found = <NamedArgument>[];

  @override
  void visitNamedArgument(NamedArgument node) {
    found.add(node);
    super.visitNamedArgument(node);
  }

  static List<NamedArgument> of(CompilationUnit unit) =>
      (NamedArguments()..run(unit)).found;

  void run(CompilationUnit unit) => unit.accept(this);
}

/// A whole number written as a literal, as `8`; null for anything else,
/// a fraction (`0.5`, a fine adjustment below the grid) included.
int? wholeLiteral(Expression e) => e is IntegerLiteral ? e.value : null;
