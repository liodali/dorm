import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../../utils/annotation_checker.dart';

/// Rule that checks if @Id field is nullable when autoIncrement is false.
///
/// When autoIncrement is false (e.g., UUID strategy or manual ID assignment),
/// the ID field must NOT be nullable because the value must be provided.
class IdNullableRule extends AnalysisRule {
  static const LintCode code = LintCode(
    'dormql_id_nullable_not_allowed',
    "ID field cannot be nullable when autoIncrement is false. The ID value must be provided.",
    correctionMessage:
        'Remove the nullable (?) from the type, or use autoIncrement: true.',
    severity: DiagnosticSeverity.ERROR,
  );

  IdNullableRule()
    : super(
        name: 'dormql_id_nullable_not_allowed',
        description:
            'Ensures @Id fields are not nullable when autoIncrement is false.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context);
    registry.addFieldDeclaration(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;
  final RuleContext context;

  _Visitor(this.rule, this.context);

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    final idAnnotation = AnnotationChecker.getIdAnnotation(node);
    if (idAnnotation == null) return;

    final autoIncrement = AnnotationChecker.getIdAutoIncrement(idAnnotation);
    final isNullable = AnnotationChecker.isNullableType(node);

    // When autoIncrement is false, nullable is not allowed
    if (!autoIncrement && isNullable) {
      rule.reportAtNode(node);
    }
  }
}
