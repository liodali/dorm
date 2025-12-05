import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../../utils/annotation_checker.dart';

/// Rule that checks if an @Entity class has a primary key defined.
///
/// Every entity must have either:
/// - A field annotated with @Id, or
/// - A class-level @PrimaryKey annotation for composite keys
class MissingIdRule extends AnalysisRule {
  static const LintCode code = LintCode(
    'dormql_missing_id',
    "Entity '{0}' must have a primary key. Add @Id to a field or @PrimaryKey to the class.",
    correctionMessage:
        'Add @Id annotation to a field, or @PrimaryKey to the class for composite keys.',
    severity: DiagnosticSeverity.ERROR,
  );

  MissingIdRule()
    : super(
        name: 'dormql_missing_id',
        description:
            'Ensures every @Entity class has a primary key defined via @Id or @PrimaryKey.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context);
    registry.addClassDeclaration(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;
  final RuleContext context;

  _Visitor(this.rule, this.context);

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    // Only check classes with @Entity annotation
    if (!AnnotationChecker.hasEntityAnnotation(node)) return;

    final hasId = _hasIdField(node);
    final hasPrimaryKey = AnnotationChecker.hasPrimaryKeyAnnotation(node);

    if (!hasId && !hasPrimaryKey) {
      rule.reportAtToken(node.name, arguments: [node.name.lexeme]);
    }
  }

  bool _hasIdField(ClassDeclaration node) {
    for (final member in node.members) {
      if (member is FieldDeclaration) {
        if (AnnotationChecker.getIdAnnotation(member) != null) {
          return true;
        }
      }
    }
    return false;
  }
}
