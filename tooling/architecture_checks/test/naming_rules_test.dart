import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The app's code, whose names are checked.
const app = 'apps/expense_tracker/lib';

/// A class, function or method whose name ends in a number, such as
/// `_read2`, tells nothing of how it differs from the one without: each
/// says what it is. Numbered values, such as the corners `x1`, `y1` or
/// the steps of `Space`, are a scale and stay.
final _numbered = RegExp(r'[A-Za-z_]\d+$');

final class _Names extends RecursiveAstVisitor<void> {
  final found = <(Token, String)>[];

  void _check(Token? name, String kind) {
    if (name == null) return;
    if (_numbered.hasMatch(name.lexeme)) {
      found.add((name, kind));
    }
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _check(node.namePart.typeName, 'class');
    super.visitClassDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _check(node.name, 'function');
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _check(node.name, 'method');
    super.visitMethodDeclaration(node);
  }
}

void main() {
  test('no class, function or method of the app is numbered', () {
    final root = p.normalize(p.join(Directory.current.path, '..', '..'));
    final offenders = <String>[];
    for (final f in Directory(p.join(root, app)).listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final result = parseString(
        content: f.readAsStringSync(),
        path: f.path,
        throwIfDiagnostics: false,
      );
      final names = _Names();
      result.unit.accept(names);
      for (final (token, kind) in names.found) {
        final line = result.lineInfo.getLocation(token.offset).lineNumber;
        offenders.add(
          '${p.relative(f.path, from: root)}:$line $kind ${token.lexeme}',
        );
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
