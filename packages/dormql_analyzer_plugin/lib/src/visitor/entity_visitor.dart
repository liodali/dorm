import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:dormql_analyzer_plugin/src/utils/annotation_checker.dart';

/// Information about an @Id annotated field.
final class IdFieldInfo {
  final FieldDeclaration field;
  final Annotation annotation;
  final String? strategy;
  final String? typeName;
  final bool isNullable;

  const IdFieldInfo({
    required this.field,
    required this.annotation,
    this.strategy,
    this.typeName,
    this.isNullable = false,
  });
}

/// Information about an entity class.
final class EntityInfo {
  final ClassDeclaration classNode;
  final String className;
  final String? tableName;
  final List<IdFieldInfo> idFields;
  final List<FieldDeclaration> fields;
  final bool hasPrimaryKeyAnnotation;
  final List<String>? primaryKeyColumns;

  const EntityInfo({
    required this.classNode,
    required this.className,
    this.tableName,
    required this.idFields,
    required this.fields,
    this.hasPrimaryKeyAnnotation = false,
    this.primaryKeyColumns,
  });
}

/// Visitor that extracts entity information from Dart AST.
final class EntityVisitor extends RecursiveAstVisitor<void> {
  final List<EntityInfo> entities = [];

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (AnnotationChecker.hasEntityAnnotation(node)) {
      final entityInfo = _extractEntityInfo(node);
      entities.add(entityInfo);
    }
    super.visitClassDeclaration(node);
  }

  EntityInfo _extractEntityInfo(ClassDeclaration node) {
    final className = node.name.lexeme;
    final tableName = _extractTableName(node);
    final idFields = <IdFieldInfo>[];
    final fields = <FieldDeclaration>[];
    final hasPrimaryKey = AnnotationChecker.hasPrimaryKeyAnnotation(node);
    final primaryKeyColumns = hasPrimaryKey
        ? _extractPrimaryKeyColumns(node)
        : null;

    // Visit all members to find fields
    for (final member in node.members) {
      if (member is FieldDeclaration) {
        // Skip ignored fields
        if (AnnotationChecker.hasIgnoreAnnotation(member)) {
          continue;
        }

        fields.add(member);

        // Check for @Id annotation
        final idAnnotation = AnnotationChecker.getIdAnnotation(member);
        if (idAnnotation != null) {
          final strategy = AnnotationChecker.getIdStrategy(idAnnotation);
          final typeName = AnnotationChecker.getFieldTypeName(member);
          final isNullable = AnnotationChecker.isNullableType(member);

          idFields.add(
            IdFieldInfo(
              field: member,
              annotation: idAnnotation,
              strategy: strategy,
              typeName: typeName,
              isNullable: isNullable,
            ),
          );
        }
      }
    }

    return EntityInfo(
      classNode: node,
      className: className,
      tableName: tableName,
      idFields: idFields,
      fields: fields,
      hasPrimaryKeyAnnotation: hasPrimaryKey,
      primaryKeyColumns: primaryKeyColumns,
    );
  }

  String? _extractTableName(ClassDeclaration node) {
    for (final annotation in node.metadata) {
      if (annotation.name.toString() == 'Entity') {
        final args = annotation.arguments?.arguments;
        if (args != null) {
          for (final arg in args) {
            if (arg is NamedExpression && arg.name.label.name == 'tableName') {
              final expr = arg.expression;
              if (expr is StringLiteral) {
                return expr.stringValue;
              }
            }
          }
        }
      }
    }
    return null;
  }

  List<String>? _extractPrimaryKeyColumns(ClassDeclaration node) {
    for (final annotation in node.metadata) {
      if (annotation.name.toString() == 'PrimaryKey') {
        final args = annotation.arguments?.arguments;
        if (args != null) {
          for (final arg in args) {
            if (arg is NamedExpression && arg.name.label.name == 'columns') {
              final expr = arg.expression;
              if (expr is ListLiteral) {
                return expr.elements
                    .whereType<StringLiteral>()
                    .map((e) => e.stringValue ?? '')
                    .where((s) => s.isNotEmpty)
                    .toList();
              }
            }
          }
        }
      }
    }
    return null;
  }
}
