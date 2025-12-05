import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

/// Information about a relationship field.
class RelationshipInfo {
  final String fieldName;
  final String
  annotationType; // 'OneToOne', 'OneToMany', 'ManyToOne', 'ManyToMany'
  final String? targetEntity;
  final String? mappedBy;
  final FieldDeclaration fieldDeclaration;
  final Annotation annotation;

  /// The resolved ClassElement for the targetEntity (if available)
  final ClassElement? targetEntityElement;

  RelationshipInfo({
    required this.fieldName,
    required this.annotationType,
    required this.targetEntity,
    required this.mappedBy,
    required this.fieldDeclaration,
    required this.annotation,
    this.targetEntityElement,
  });

  /// Check if targetEntity has @Entity annotation
  bool get isTargetEntityValid {
    if (targetEntityElement == null) return false;
    for (final m in targetEntityElement!.metadata.annotations) {
      final element = m.element;
      if (element is ConstructorElement) {
        if (element.enclosingElement.name == 'Entity') {
          return true;
        }
      }
    }
    return false;
  }
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
        final targetEntityElement = _getTargetEntityElement(annotation);
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
            targetEntityElement: targetEntityElement,
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

  /// Get the resolved ClassElement for targetEntity parameter
  ClassElement? _getTargetEntityElement(Annotation annotation) {
    final args = annotation.arguments?.arguments;
    if (args != null) {
      for (final arg in args) {
        if (arg is NamedExpression && arg.name.label.name == 'targetEntity') {
          final expr = arg.expression;
          Element? element;
          if (expr is SimpleIdentifier) {
            element = expr.element;
          } else if (expr is PrefixedIdentifier) {
            element = expr.element;
          }
          if (element is ClassElement) {
            return element;
          }
        }
      }
    }
    return null;
  }
}
