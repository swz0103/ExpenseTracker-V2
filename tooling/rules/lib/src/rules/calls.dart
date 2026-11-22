import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../engine.dart';

/// A call written `target.name(args)` or `name(args)`, whether the syntax
/// tree has it as a method invocation or as a constructor call. Without
/// resolution `DateTime.now()` is a method invocation, and `new
/// DateTime.now()` an instance creation; both come out as target
/// `DateTime`, name `now`. An unnamed constructor call `Stopwatch()` comes
/// out as target null, name `Stopwatch`.
final class Call {
  const Call(this.target, this.name, this.node, this.arguments);

  final String? target;
  final String name;
  final AstNode node;
  final NodeList<Argument> arguments;

  bool matches(String? targetName, String callName) =>
      target == targetName && name == callName;
}

final class _Calls extends RecursiveAstVisitor<void> {
  final found = <Call>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target;
    found.add(
      Call(
        target is SimpleIdentifier ? target.name : null,
        node.methodName.name,
        node,
        node.argumentList.arguments,
      ),
    );
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final namedType = node.constructorName.type;
    final type = namedType.name.lexeme;
    final named = node.constructorName.name?.name;
    // Unresolved, `new DateTime.now()` has `DateTime` as an import prefix.
    final prefix = namedType.importPrefix?.name.lexeme;
    found.add(
      Call(
        named != null ? type : prefix,
        named ?? type,
        node,
        node.argumentList.arguments,
      ),
    );
    super.visitInstanceCreationExpression(node);
  }
}

/// Every call in [file], in source order of discovery.
List<Call> callsIn(SourceFile file) {
  final visitor = _Calls();
  file.unit.accept(visitor);
  return visitor.found;
}

/// Whether [call] is `DateTime.now()`.
bool isDateTimeNow(Call call) => call.matches('DateTime', 'now');
