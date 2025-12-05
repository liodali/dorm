import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../../utils/annotation_checker.dart';

/// Rule that checks if @Id annotation strategy matches the field type.
///
/// - UUID strategy requires String type
/// - AutoIncrement/Serial strategies require int or BigInt type
class IdTypeMismatchRule extends MultiAnalysisRule {
  static const LintCode uuidCode = LintCode(
    'dormql_uuid_requires_string',
    "UUID strategy requires String type, but field is '{0}'.",
    correctionMessage:
        'Change the field type to String, or use a different ID strategy.',
    severity: DiagnosticSeverity.ERROR,
  );

  static const LintCode autoIncrementCode = LintCode(
    'dormql_autoincrement_requires_int',
    "AutoIncrement/Serial strategy requires int or BigInt type, but field is '{0}'.",
    correctionMessage:
        'Change the field type to int or BigInt, or use UUID strategy for String.',
    severity: DiagnosticSeverity.ERROR,
  );

  IdTypeMismatchRule()
    : super(
        name: 'dormql_id_type_mismatch',
        description:
            'Ensures @Id strategy matches the field type (UUID->String, AutoIncrement->int/BigInt).',
      );

  @override
  List<LintCode> get diagnosticCodes => [uuidCode, autoIncrementCode];

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
  final IdTypeMismatchRule rule;
  final RuleContext context;

  _Visitor(this.rule, this.context);

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    final idAnnotation = AnnotationChecker.getIdAnnotation(node);
    if (idAnnotation == null) return;

    final strategy = AnnotationChecker.getIdStrategy(idAnnotation);
    final typeName = AnnotationChecker.getFieldTypeName(node);

    if (typeName == null) return;

    // Check UUID strategy requires String
    if (_isUuidStrategy(strategy)) {
      if (typeName != 'String') {
        rule.reportAtNode(
          node,
          diagnosticCode: IdTypeMismatchRule.uuidCode,
          arguments: [typeName],
        );
      }
    }
    // Check AutoIncrement/Serial requires int or BigInt
    else if (_isAutoIncrementStrategy(strategy)) {
      if (!_isIntegerType(typeName)) {
        rule.reportAtNode(
          node,
          diagnosticCode: IdTypeMismatchRule.autoIncrementCode,
          arguments: [typeName],
        );
      }
    }
  }

  bool _isUuidStrategy(String? strategy) {
    return strategy == 'uuid';
  }

  bool _isAutoIncrementStrategy(String? strategy) {
    // null means default, which is autoIncrement
    return strategy == null ||
        strategy == 'serial' ||
        strategy == 'autoIncrement' ||
        strategy == 'autoIncrementSqlite' ||
        strategy == 'postgres' ||
        strategy == 'mysql' ||
        strategy == 'sqlite';
  }

  bool _isIntegerType(String typeName) {
    return typeName == 'int' || typeName == 'BigInt';
  }
}
