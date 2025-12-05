import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
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

  static const LintCode invalidTargetCode = LintCode(
    'dormql_onetoone_invalid_target',
    "@OneToOne targetEntity '{0}' is not an @Entity class.",
    correctionMessage:
        'Specify a class annotated with @Entity as targetEntity.',
    severity: DiagnosticSeverity.ERROR,
  );

  static const LintCode mappedByNotFoundCode = LintCode(
    'dormql_onetoone_mappedby_not_found',
    "@OneToOne mappedBy field '{0}' not found in target entity '{1}'.",
    correctionMessage: 'Verify the field name exists in the target entity.',
    severity: DiagnosticSeverity.ERROR,
  );

  static const LintCode mappedByNotOneToOneCode = LintCode(
    'dormql_onetoone_mappedby_not_onetoone',
    "@OneToOne mappedBy field '{0}' in '{1}' must have @OneToOne annotation.",
    correctionMessage: 'Add @OneToOne annotation to the referenced field.',
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
    invalidTargetCode,
    mappedByNotFoundCode,
    mappedByNotOneToOneCode,
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

    // 2. Check if targetEntity is a valid @Entity class
    final targetElement = relationship.targetEntityElement;
    if (targetElement != null && !relationship.isTargetEntityValid) {
      rule.reportAtNode(
        relationship.fieldDeclaration,
        diagnosticCode: OneToOneRules.invalidTargetCode,
        arguments: [relationship.targetEntity!],
      );
      return;
    }

    // 3. Check mappedBy validation
    if (relationship.mappedBy != null && targetElement != null) {
      _validateMappedBy(relationship, targetElement);
    }
  }

  void _validateMappedBy(
    RelationshipInfo relationship,
    ClassElement targetElement,
  ) {
    final mappedBy = relationship.mappedBy!;

    // Find the field in target entity
    final targetField = targetElement.fields
        .where((f) => f.name == mappedBy)
        .firstOrNull;

    final targetName = targetElement.name ?? 'Unknown';

    if (targetField == null) {
      rule.reportAtNode(
        relationship.fieldDeclaration,
        diagnosticCode: OneToOneRules.mappedByNotFoundCode,
        arguments: [mappedBy, targetName],
      );
      return;
    }

    // Check if the target field has @OneToOne annotation
    bool hasOneToOne = false;
    for (final annotation in targetField.metadata.annotations) {
      final element = annotation.element;
      if (element is ConstructorElement) {
        if (element.enclosingElement.name == 'OneToOne') {
          hasOneToOne = true;
          break;
        }
      }
    }

    if (!hasOneToOne) {
      rule.reportAtNode(
        relationship.fieldDeclaration,
        diagnosticCode: OneToOneRules.mappedByNotOneToOneCode,
        arguments: [mappedBy, targetName],
      );
    }
  }
}
