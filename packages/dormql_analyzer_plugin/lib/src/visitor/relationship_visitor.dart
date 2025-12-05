import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Information about a relationship field.
class RelationshipInfo {
  final String fieldName;
  final String
  annotationType; // 'OneToOne', 'OneToMany', 'ManyToOne', 'ManyToMany'
  final String? targetEntity;
  final String? mappedBy;
  final FieldDeclaration fieldDeclaration;
  final Annotation annotation;

  RelationshipInfo({
    required this.fieldName,
    required this.annotationType,
    required this.targetEntity,
    required this.mappedBy,
    required this.fieldDeclaration,
    required this.annotation,
  });
}

/// Visitor that extracts relationship information from entity classes.
class RelationshipVisitor extends SimpleAstVisitor<void> {
  final List<RelationshipInfo> relationships = [];
  final ClassDeclaration classDecl;

  RelationshipVisitor(this.classDecl);

  void visit() {
    visitClassDeclaration(classDecl);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    for (final member in node.members) {
      if (member is FieldDeclaration) {
        _checkField(member);
      }
    }
  }

  void _checkField(FieldDeclaration field) {
    for (final annotation in field.metadata) {
      final relType = _getRelationshipType(annotation);
      if (relType != null) {
        final targetEntity = _getTargetEntity(annotation);
        final mappedBy = _getMappedBy(annotation);
        final fieldName = field.fields.variables.first.name.lexeme;

        relationships.add(
          RelationshipInfo(
            fieldName: fieldName,
            annotationType: relType,
            targetEntity: targetEntity,
            mappedBy: mappedBy,
            fieldDeclaration: field,
            annotation: annotation,
          ),
        );
      }
    }
  }

  String? _getRelationshipType(Annotation annotation) {
    final name = annotation.name;
    if (name is SimpleIdentifier) {
      final annotationName = name.name;
      if ([
        'OneToOne',
        'OneToMany',
        'ManyToOne',
        'ManyToMany',
      ].contains(annotationName)) {
        return annotationName;
      }
    }
    return null;
  }

  String? _getTargetEntity(Annotation annotation) {
    final args = annotation.arguments?.arguments;
    if (args != null) {
      for (final arg in args) {
        if (arg is NamedExpression && arg.name.label.name == 'targetEntity') {
          final expr = arg.expression;
          if (expr is Identifier) {
            return expr.name;
          }
        }
      }
    }
    return null;
  }

  String? _getMappedBy(Annotation annotation) {
    final args = annotation.arguments?.arguments;
    if (args != null) {
      for (final arg in args) {
        if (arg is NamedExpression && arg.name.label.name == 'mappedBy') {
          final expr = arg.expression;
          if (expr is SimpleStringLiteral) {
            return expr.value;
          }
        }
      }
    }
    return null;
  }
}
