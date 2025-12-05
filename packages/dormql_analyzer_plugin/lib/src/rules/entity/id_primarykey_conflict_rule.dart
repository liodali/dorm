import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../../utils/annotation_checker.dart';

/// Rule that checks for conflicts between @Id and @PrimaryKey annotations.
///
/// An entity cannot have both:
/// - @Id on a field AND @PrimaryKey on the class
/// - @Id AND @Column(primaryKey: true) on the same field
class IdPrimaryKeyConflictRule extends MultiAnalysisRule {
  static const LintCode classConflictCode = LintCode(
    'dormql_id_primarykey_conflict',
    "Cannot use both @Id and @PrimaryKey in entity '{0}'.",
    correctionMessage:
        'Use @Id for single-field primary keys, or @PrimaryKey for composite keys, but not both.',
  );

  static const LintCode fieldConflictCode = LintCode(
    'dormql_id_column_primarykey_conflict',
    'Cannot use both @Id and @Column(primaryKey: true) on the same field.',
    correctionMessage: 'Use @Id alone for primary key fields.',
  );

  IdPrimaryKeyConflictRule()
    : super(
        name: 'dormql_id_primarykey_conflict',
        description:
            'Ensures @Id and @PrimaryKey/@Column(primaryKey) are not used together incorrectly.',
      );

  @override
  List<LintCode> get diagnosticCodes => [classConflictCode, fieldConflictCode];

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context);
    registry.addClassDeclaration(this, visitor);
    registry.addFieldDeclaration(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final IdPrimaryKeyConflictRule rule;
  final RuleContext context;

  _Visitor(this.rule, this.context);

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    // Only check classes with @Entity annotation
    if (!AnnotationChecker.hasEntityAnnotation(node)) return;

    final hasId = _hasIdField(node);
    final hasPrimaryKey = AnnotationChecker.hasPrimaryKeyAnnotation(node);

    if (hasId && hasPrimaryKey) {
      rule.reportAtToken(
        node.name,
        diagnosticCode: IdPrimaryKeyConflictRule.classConflictCode,
        arguments: [node.name.lexeme],
      );
    }
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    final hasId = AnnotationChecker.getIdAnnotation(node) != null;
    final hasColumnPK = AnnotationChecker.hasColumnPrimaryKey(node);

    if (hasId && hasColumnPK) {
      rule.reportAtNode(
        node,
        diagnosticCode: IdPrimaryKeyConflictRule.fieldConflictCode,
      );
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
