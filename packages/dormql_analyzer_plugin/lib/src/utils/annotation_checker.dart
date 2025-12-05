import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// Utility class for checking DormQL annotations on AST nodes.
final class AnnotationChecker {
  const AnnotationChecker._();

  /// Checks if a class has the @Entity annotation.
  static bool hasEntityAnnotation(ClassDeclaration node) {
    return node.metadata.any((m) => _isAnnotation(m, 'Entity'));
  }

  /// Checks if a field has the @Id annotation.
  static bool hasIdAnnotation(FieldDeclaration node) {
    return node.metadata.any((m) => _isAnnotation(m, 'Id'));
  }

  /// Checks if a class has the @PrimaryKey annotation.
  static bool hasPrimaryKeyAnnotation(ClassDeclaration node) {
    return node.metadata.any((m) => _isAnnotation(m, 'PrimaryKey'));
  }

  /// Checks if a field has @Column(primaryKey: true).
  static bool hasColumnPrimaryKey(FieldDeclaration node) {
    for (final annotation in node.metadata) {
      if (_isAnnotation(annotation, 'Column')) {
        final args = annotation.arguments?.arguments;
        if (args != null) {
          for (final arg in args) {
            if (arg is NamedExpression &&
                arg.name.label.name == 'primaryKey' &&
                arg.expression is BooleanLiteral &&
                (arg.expression as BooleanLiteral).value == true) {
              return true;
            }
          }
        }
      }
    }
    return false;
  }

  /// Gets the @Id annotation from a field, if present.
  static Annotation? getIdAnnotation(FieldDeclaration node) {
    for (final annotation in node.metadata) {
      if (_isAnnotation(annotation, 'Id')) {
        return annotation;
      }
    }
    return null;
  }

  /// Gets the ID strategy from an @Id annotation.
  /// Returns the strategy name (e.g., 'uuid', 'serial', 'autoIncrement').
  static String? getIdStrategy(Annotation annotation) {
    // Check for named constructors like Id.uuid(), Id.postgres(), etc.
    final name = annotation.name;
    if (name is PrefixedIdentifier) {
      return name.identifier.name; // 'uuid', 'postgres', 'mysql', 'sqlite'
    }

    // Check for strategy parameter in default constructor
    final args = annotation.arguments?.arguments;
    if (args != null) {
      for (final arg in args) {
        if (arg is NamedExpression && arg.name.label.name == 'strategy') {
          final expr = arg.expression;
          if (expr is PrefixedIdentifier) {
            return expr.identifier.name; // e.g., 'uuid', 'serial'
          }
        }
      }
    }

    return null; // Default strategy
  }

  /// Gets the autoIncrement value from an @Id annotation.
  /// Returns true by default (as per @Id annotation default).
  static bool getIdAutoIncrement(Annotation annotation) {
    // Check for named constructors - they have predefined autoIncrement values
    final name = annotation.name;
    if (name is PrefixedIdentifier) {
      final constructorName = name.identifier.name;
      // uuid constructor has autoIncrement = false
      if (constructorName == 'uuid') {
        return false;
      }
      // postgres, mysql, sqlite constructors have autoIncrement = true
      return true;
    }

    // Check for autoIncrement parameter in default constructor
    final args = annotation.arguments?.arguments;
    if (args != null) {
      for (final arg in args) {
        if (arg is NamedExpression && arg.name.label.name == 'autoIncrement') {
          final expr = arg.expression;
          if (expr is BooleanLiteral) {
            return expr.value;
          }
        }
      }
    }

    return true; // Default is autoIncrement = true
  }

  /// Checks if a field has any relationship annotation.
  static bool hasRelationshipAnnotation(FieldDeclaration node) {
    return node.metadata.any(
      (m) =>
          _isAnnotation(m, 'OneToOne') ||
          _isAnnotation(m, 'OneToMany') ||
          _isAnnotation(m, 'ManyToOne') ||
          _isAnnotation(m, 'ManyToMany'),
    );
  }

  /// Gets the relationship annotation type name if present.
  static String? getRelationshipType(FieldDeclaration node) {
    for (final annotation in node.metadata) {
      final name = _getAnnotationName(annotation);
      if (['OneToOne', 'OneToMany', 'ManyToOne', 'ManyToMany'].contains(name)) {
        return name;
      }
    }
    return null;
  }

  /// Checks if a class has the @Db annotation.
  static bool hasDbAnnotation(ClassDeclaration node) {
    return node.metadata.any((m) => _isAnnotation(m, 'Db'));
  }

  /// Gets the @Db annotation from a class, if present.
  static Annotation? getDbAnnotation(ClassDeclaration node) {
    for (final annotation in node.metadata) {
      if (_isAnnotation(annotation, 'Db')) {
        return annotation;
      }
    }
    return null;
  }

  /// Checks if a field has the @Ignore annotation.
  static bool hasIgnoreAnnotation(FieldDeclaration node) {
    return node.metadata.any((m) => _isAnnotation(m, 'Ignore'));
  }

  /// Gets the Dart type name from a field declaration.
  static String? getFieldTypeName(FieldDeclaration node) {
    final type = node.fields.type;
    if (type is NamedType) {
      return type.element?.name;
    }
    return null;
  }

  /// Checks if a type is nullable.
  static bool isNullableType(FieldDeclaration node) {
    final type = node.fields.type;
    if (type is NamedType) {
      return type.question != null;
    }
    return false;
  }

  static bool _isAnnotation(Annotation annotation, String name) {
    return _getAnnotationName(annotation) == name;
  }

  static String? _getAnnotationName(Annotation annotation) {
    final name = annotation.name;
    if (name is SimpleIdentifier) {
      return name.name;
    } else if (name is PrefixedIdentifier) {
      return name.prefix.name;
    }
    return null;
  }
}

/// Extension on DartType for easier type checking.
extension DartTypeExtension on DartType {
  bool get isInt => isDartCoreInt;
  bool get isString => isDartCoreString;
  bool get isBool => isDartCoreBool;
  bool get isDouble => isDartCoreDouble;

  bool get isBigInt {
    final element = this.element;
    return element is ClassElement && element.name == 'BigInt';
  }

  bool get isIntOrBigInt => isInt || isBigInt;
}
