import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../../utils/annotation_checker.dart';

/// Rule that checks if @Column columnType matches the Dart field type.
///
/// Validates type compatibility:
/// - ColumnType.integer/serial/bigserial -> int, BigInt
/// - ColumnType.text -> String
/// - ColumnType.boolean -> bool
/// - ColumnType.decimal/real -> double, num
/// - ColumnType.timestamp -> DateTime
/// - ColumnType.uuid -> String
/// - ColumnType.json -> String, Map, List
class ColumnTypeMismatchRule extends AnalysisRule {
  static const LintCode code = LintCode(
    'dormql_column_type_mismatch',
    "Column type '{0}' is incompatible with Dart type '{1}'.",
    correctionMessage:
        'Change the columnType to match the Dart type, or change the field type.',
    severity: DiagnosticSeverity.WARNING,
  );

  ColumnTypeMismatchRule()
    : super(
        name: 'dormql_column_type_mismatch',
        description:
            'Ensures @Column columnType is compatible with the Dart field type.',
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
    final columnAnnotation = _getColumnAnnotation(node);
    if (columnAnnotation == null) return;

    final columnType = _getColumnType(columnAnnotation);
    if (columnType == null) return; // Default columnType, no validation needed

    final dartType = AnnotationChecker.getFieldTypeName(node);
    if (dartType == null) return;

    if (!_isTypeCompatible(columnType, dartType)) {
      rule.reportAtNode(node, arguments: [columnType, dartType]);
    }
  }

  Annotation? _getColumnAnnotation(FieldDeclaration node) {
    for (final annotation in node.metadata) {
      final name = annotation.name;
      if (name is SimpleIdentifier && name.name == 'Column') {
        return annotation;
      }
    }
    return null;
  }

  String? _getColumnType(Annotation annotation) {
    final args = annotation.arguments?.arguments;
    if (args != null) {
      for (final arg in args) {
        if (arg is NamedExpression && arg.name.label.name == 'columnType') {
          final expr = arg.expression;
          if (expr is PrefixedIdentifier) {
            return expr.identifier.name; // e.g., 'integer', 'text', 'boolean'
          }
        }
      }
    }
    return null;
  }

  bool _isTypeCompatible(String columnType, String dartType) {
    switch (columnType) {
      case 'integer':
      case 'serial':
      case 'bigserial':
        return dartType == 'int' || dartType == 'BigInt';
      case 'text':
        return dartType == 'String';
      case 'boolean':
        return dartType == 'bool';
      case 'decimal':
      case 'real':
        return dartType == 'double' || dartType == 'num';
      case 'timestamp':
        return dartType == 'DateTime';
      case 'uuid':
        return dartType == 'String';
      case 'json':
        return dartType == 'String' ||
            dartType == 'Map' ||
            dartType == 'List' ||
            dartType.startsWith('Map<') ||
            dartType.startsWith('List<');
      default:
        return true; // Unknown column type, don't report
    }
  }
}
