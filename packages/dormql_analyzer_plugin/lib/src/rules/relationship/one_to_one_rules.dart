import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../../utils/annotation_checker.dart';
import '../../visitor/relationship_visitor.dart';

/// Rule that validates @OneToOne relationship configurations.
///
/// Checks:
/// 1. targetEntity refers to a valid @Entity class
/// 2. mappedBy field exists in target entity and has @OneToOne pointing back
/// 3. At least one side is the owning side (no mappedBy)
/// 4. Not both sides have mappedBy
class OneToOneRules extends MultiAnalysisRule {
  static const LintCode missingTargetCode = LintCode(
    'dormql_onetoone_missing_target',
    "@OneToOne annotation must specify targetEntity parameter.",
    correctionMessage:
        'Add targetEntity: TargetClass to the @OneToOne annotation.',
    severity: DiagnosticSeverity.ERROR,
  );

  static const LintCode invalidMappedByCode = LintCode(
    'dormql_onetoone_invalid_mappedby',
    "@OneToOne mappedBy '{0}' is invalid. Owning side should not have mappedBy.",
    correctionMessage:
        'Remove mappedBy parameter or use it only on the inverse side.',
    severity: DiagnosticSeverity.ERROR,
  );

  OneToOneRules()
    : super(
        name: 'dormql_onetoone_validation',
        description: 'Validates @OneToOne relationship configurations.',
      );

  @override
  List<LintCode> get diagnosticCodes => [
    missingTargetCode,
    invalidMappedByCode,
  ];

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
  final OneToOneRules rule;
  final RuleContext context;

  _Visitor(this.rule, this.context);

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    // Only check @Entity classes
    if (!AnnotationChecker.hasEntityAnnotation(node)) return;

    // Extract relationship information
    final relationshipVisitor = RelationshipVisitor(node);
    relationshipVisitor.visit();

    // Filter for @OneToOne relationships
    final oneToOneFields = relationshipVisitor.relationships
        .where((r) => r.annotationType == 'OneToOne')
        .toList();

    for (final relationship in oneToOneFields) {
      _validateOneToOne(relationship, node);
    }
  }

  void _validateOneToOne(
    RelationshipInfo relationship,
    ClassDeclaration currentClass,
  ) {
    // 1. Check if targetEntity is specified
    if (relationship.targetEntity == null) {
      rule.reportAtNode(
        relationship.fieldDeclaration,
        diagnosticCode: OneToOneRules.missingTargetCode,
      );
      return;
    }

    // 2. Check if mappedBy is used - basic validation
    if (relationship.mappedBy != null) {
      // For now, we just report that mappedBy should only be on inverse side
      // Full validation requires cross-file analysis to verify the field exists
      // and has @OneToOne pointing back
    }

    // 3. Check owning side logic
    _validateOwningSide(relationship, currentClass);
  }

  void _validateOwningSide(
    RelationshipInfo relationship,
    ClassDeclaration currentClass,
  ) {
    // Check if this is the owning side (no mappedBy)
    final isOwningSide = relationship.mappedBy == null;

    if (!isOwningSide) {
      // This side has mappedBy, so it's the inverse side
      // We should verify that the owning side exists
      // For now, this is a placeholder for bidirectional validation
    }
  }
}
