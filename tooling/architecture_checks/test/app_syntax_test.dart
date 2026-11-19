import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The app's rules that are about its code, read from the syntax tree
/// rather than matched as text: a comment, a string or another way of
/// writing the same thing neither trips them nor slips past them.
/// docs/design.md and docs/architecture.md say why each rule is there.
void main() {
  final root = p.normalize(p.join(Directory.current.path, '..', '..'));
  final lib = p.join(root, 'apps', 'expense_tracker', 'lib');
  final units = {
    for (final f in Directory(lib).listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart'))
        p.relative(f.path, from: lib).replaceAll(r'\', '/'): parseString(
          content: f.readAsStringSync(),
          path: f.path,
          throwIfDiagnostics: false,
        ).unit,
  };
  List<String> found(bool Function(String path) where, _Finder finder) => [
    for (final MapEntry(key: path, value: unit) in units.entries)
      if (where(path))
        for (final what in (finder..found.clear()).run(unit)) '$path: $what',
  ];

  test('colours are named in core/design_system, not written in a page', () {
    // A category's colour is data, kept with the ledger and made up for
    // the preview; the design system names every other colour.
    const exempt = [
      'src/core/design_system/',
      'src/core/ledger/',
      '/model/',
      'src/app/demo/',
    ];
    final faults = found(
      (path) => !exempt.any(path.contains),
      _ColourLiterals(),
    );
    expect(faults, isEmpty, reason: 'name the colour in theme.dart');
  });

  test('words take a size from the type scale', () {
    // Also a size picked between two, as `fontSize: done ? 16 : 15`; a
    // size worked out from another, as `size * 0.44`, may stand.
    final faults = found(
      (path) => !path.endsWith('core/design_system/type.dart'),
      _FontSizeLiterals(),
    );
    expect(faults, isEmpty, reason: 'use TextSize from type.dart');
  });

  test('casts of outside data only become fewer', () {
    // Read through JsonFields (core/formatting/json_fields.dart) instead:
    // a cast throws a TypeError for one field of the wrong kind and takes
    // the rest down with it. What is left is the ledger's own rows.
    const most = 18;
    final casts = found((_) => true, _Casts());
    expect(casts.length, lessThanOrEqualTo(most), reason: casts.join('\n'));
    expect(casts.length, most, reason: 'fewer now: lower `most`');
  });

  test('fewer screens take the whole ledger', () {
    // A screen or a model that needs only the entries, or the reports,
    // takes that part (EntryReader, ReportService, exported by
    // ledger.dart): it says what it uses, and a test gives it only that.
    const most = 82;
    final whole = [
      for (final MapEntry(key: path, value: unit) in units.entries)
        if (path.startsWith('src/features/') || path.startsWith('src/app/'))
          if ((_LedgerUses()..found.clear()).run(unit).isNotEmpty) path,
    ];
    expect(whole.length, lessThanOrEqualTo(most), reason: 'take the part');
    expect(whole.length, most, reason: 'fewer now: lower `most`');
  });
}

/// Walks a unit and keeps a line for each thing it is looking for.
abstract class _Finder extends RecursiveAstVisitor<void> {
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
final class _ColourLiterals extends _Finder {
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
final class _FontSizeLiterals extends _Finder {
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
final class _Casts extends _Finder {
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
final class _LedgerUses extends _Finder {
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
