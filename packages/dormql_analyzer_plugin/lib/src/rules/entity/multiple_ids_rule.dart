import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../../utils/annotation_checker.dart';

/// Rule that checks if an @Entity class has multiple @Id annotations.
///
/// Only one @Id annotation is allowed per entity. For composite primary keys,
/// use @PrimaryKey at the class level instead.
class MultipleIdsRule extends AnalysisRule {
  static const LintCode code = LintCode(
    'dormql_multiple_ids',
    "Entity '{0}' has multiple @Id annotations. Use only one @Id, or use @PrimaryKey for composite keys.",
    correctionMessage:
        'Remove extra @Id annotations, or use @PrimaryKey for composite primary keys.',
  );

  MultipleIdsRule()
    : super(
        name: 'dormql_multiple_ids',
        description: 'Ensures @Entity classes have at most one @Id annotation.',
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

    final idFields = _getIdFields(node);

    // Report on each extra @Id annotation (skip the first one)
    if (idFields.length > 1) {
      for (var i = 1; i < idFields.length; i++) {
        final annotation = AnnotationChecker.getIdAnnotation(idFields[i]);
        if (annotation != null) {
          rule.reportAtNode(annotation, arguments: [node.name.lexeme]);
        }
      }
    }
  }

  List<FieldDeclaration> _getIdFields(ClassDeclaration node) {
    final idFields = <FieldDeclaration>[];
    for (final member in node.members) {
      if (member is FieldDeclaration) {
        if (AnnotationChecker.getIdAnnotation(member) != null) {
          idFields.add(member);
        }
      }
    }
    return idFields;
  }
}
