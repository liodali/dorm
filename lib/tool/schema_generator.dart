import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:collection/collection.dart';
import 'package:dorm/src/annotation.dart';
import 'package:source_gen/source_gen.dart';

class SchemaGenerator extends GeneratorForAnnotation<Entity> {
  @override
  Future<String> generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) async {
    final classElement = element as ClassElement;
    final className = element.name;
    final tableName =
        annotation.peek('tableName')?.stringValue ?? _toTableName(className!);

    // Collect all field names for validation
    final fieldNames = _collectFieldNames(classElement);

    // Validate class-level annotations
    _validateClassAnnotations(classElement, fieldNames);

    final schemaContent = _generateSchema(classElement, tableName, fieldNames);
    final indexes = _generateIndexes(classElement, tableName);
    final foreignKeys = _generateForeignKeys(classElement);
    final primaryKeyColumns = _generatePrimaryKeyColumns(classElement);
    final uniqueConstraints = _generateUniqueConstraints(classElement);
    final checkConstraints = _generateCheckConstraints(classElement);

    return '''
/// Schema extension for $className
extension ${className}Schema on $className {
  /// Get the database schema for this entity
  static DatabaseSchema get schema => _${_toCamelCase(className!)}Schema;
  
  /// Table name for this entity
  static String get tableName => '$tableName';
}

/// Generated schema for $className
const _${_toCamelCase(className)}Schema = DatabaseSchema(
  tableName: '$tableName',
  columns: [
    $schemaContent
  ],${indexes.isNotEmpty ? '''
  indexes: [
    $indexes
  ],''' : ''}${foreignKeys.isNotEmpty ? '''
  foreignKeys: [
    $foreignKeys
  ],''' : ''}${primaryKeyColumns.isNotEmpty ? '''
  primaryKeyColumns: [$primaryKeyColumns],''' : ''}${uniqueConstraints.isNotEmpty ? '''
  uniqueConstraints: [
    $uniqueConstraints
  ],''' : ''}${checkConstraints.isNotEmpty ? '''
  checkConstraints: [
    $checkConstraints
  ],''' : ''}
);
    ''';
  }

  /// Generate indexes from @Index annotations
  String _generateIndexes(ClassElement element, String tableName) {
    final indexes = <String>[];

    for (final annotation in element.metadata.annotations) {
      if (annotation.element?.enclosingElement?.name == 'Index') {
        final value = annotation.computeConstantValue();
        if (value == null) continue;

        final columns = value.getField('columns')?.toListValue();
        if (columns == null || columns.isEmpty) continue;

        final columnNames = columns
            .map((c) => "'${c.toStringValue()}'")
            .join(', ');
        final name =
            value.getField('name')?.toStringValue() ??
            'idx_${tableName}_${columns.map((c) => c.toStringValue()).join('_')}';
        final unique = value.getField('unique')?.toBoolValue() ?? false;

        indexes.add(
          "IndexSchema(name: '$name', columns: [$columnNames], unique: $unique)",
        );
      }
    }

    return indexes.join(',\n    ');
  }

  /// Generate foreign keys from fields
  String _generateForeignKeys(ClassElement element) {
    final foreignKeys = <String>[];

    for (final field in element.fields) {
      if (field.isStatic) continue;
      if (_isRelationshipField(field)) continue;
      if (_hasAnnotation(field, 'Ignore')) continue;

      // Check for ForeignKeyConstraint annotation
      final fkAnnotation = _getFieldAnnotation(field, 'ForeignKeyConstraint');
      if (fkAnnotation != null) {
        final fk = _processForeignKeyAnnotation(field, fkAnnotation);
        if (fk != null) foreignKeys.add(fk);
      }
    }

    return foreignKeys.join(',\n    ');
  }

  /// Generate primary key columns from @PrimaryKey annotation
  String _generatePrimaryKeyColumns(ClassElement element) {
    for (final annotation in element.metadata.annotations) {
      if (annotation.element?.enclosingElement?.name == 'PrimaryKey') {
        final value = annotation.computeConstantValue();
        final columns = value?.getField('columns')?.toListValue();
        if (columns != null && columns.isNotEmpty) {
          return columns.map((c) => "'${c.toStringValue()}'").join(', ');
        }
      }
    }
    return '';
  }

  /// Generate unique constraints from class-level @Unique annotations
  String _generateUniqueConstraints(ClassElement element) {
    final constraints = <String>[];

    for (final annotation in element.metadata.annotations) {
      if (annotation.element?.enclosingElement?.name == 'Unique') {
        final value = annotation.computeConstantValue();
        final columns = value?.getField('columns')?.toListValue();
        if (columns != null && columns.isNotEmpty) {
          final columnNames = columns
              .map((c) => "'${c.toStringValue()}'")
              .join(', ');
          final name = value?.getField('name')?.toStringValue();
          final nameParam = name != null ? ", name: '$name'" : '';
          constraints.add(
            "UniqueConstraint(columns: [$columnNames]$nameParam)",
          );
        }
      }
    }

    return constraints.join(',\n    ');
  }

  /// Generate check constraints from @Check annotations
  String _generateCheckConstraints(ClassElement element) {
    final constraints = <String>[];

    for (final field in element.fields) {
      if (field.isStatic) continue;

      final checkAnnotation = _getFieldAnnotation(field, 'Check');
      if (checkAnnotation != null) {
        final value = checkAnnotation.computeConstantValue();
        final expression = value?.getField('expression')?.toStringValue();
        final name = value?.getField('name')?.toStringValue();
        if (expression != null) {
          final nameParam = name != null ? ", name: '$name'" : '';
          constraints.add(
            "CheckConstraint(expression: '$expression'$nameParam)",
          );
        }
      }
    }

    return constraints.join(',\n    ');
  }

  /// Collect all field names (as snake_case column names)
  Set<String> _collectFieldNames(ClassElement element) {
    final names = <String>{};
    for (final field in element.fields) {
      if (field.isStatic) continue;
      if (_isRelationshipField(field)) continue;
      if (_hasAnnotation(field, 'Ignore')) continue;
      names.add(_toSnakeCase(field.displayName));
    }
    return names;
  }

  /// Validate class-level annotations (PrimaryKey, Unique, Index)
  void _validateClassAnnotations(ClassElement element, Set<String> fieldNames) {
    for (final annotation in element.metadata.annotations) {
      final annotationName = annotation.element?.enclosingElement?.name;

      if (annotationName == 'PrimaryKey') {
        _validateColumnsExist(annotation, 'PrimaryKey', fieldNames);
      } else if (annotationName == 'Unique') {
        final columns = _getAnnotationListValue(annotation, 'columns');
        if (columns != null && columns.isNotEmpty) {
          _validateColumnsExist(annotation, 'Unique', fieldNames);
        }
      } else if (annotationName == 'Index') {
        _validateColumnsExist(annotation, 'Index', fieldNames);
      }
    }
  }

  /// Validate that all columns in an annotation exist in the entity
  void _validateColumnsExist(
    ElementAnnotation annotation,
    String annotationName,
    Set<String> fieldNames,
  ) {
    final columns = _getAnnotationListValue(annotation, 'columns');
    if (columns == null) return;

    for (final column in columns) {
      final columnName = column.toStringValue();
      if (columnName != null && !fieldNames.contains(columnName)) {
        throw InvalidGenerationSourceError(
          '@$annotationName references column "$columnName" which does not exist. '
          'Available columns: ${fieldNames.join(', ')}',
          element: annotation.element,
        );
      }
    }
  }

  /// Get a list value from an annotation
  List<DartObject>? _getAnnotationListValue(
    ElementAnnotation annotation,
    String fieldName,
  ) {
    final value = annotation.computeConstantValue();
    return value?.getField(fieldName)?.toListValue();
  }

  String _generateSchema(
    ClassElement element,
    String tableName,
    Set<String> fieldNames,
  ) {
    final columns = <String>[];
    final foreignKeys = <String>[];
    final constraints = <String>[];

    // Process class-level annotations
    _processClassConstraints(element, constraints, fieldNames);

    for (final field in element.fields) {
      if (field.isStatic) continue;

      // Skip relationship fields - they are not columns
      if (_isRelationshipField(field)) continue;

      // Skip ignored fields
      if (_hasAnnotation(field, 'Ignore')) continue;

      final column = _readColumnAnnotation(field, fieldNames);
      if (column != null) {
        columns.add(column);

        // Check for ForeignKeyConstraint annotation
        final fkAnnotation = _getFieldAnnotation(field, 'ForeignKeyConstraint');
        if (fkAnnotation != null) {
          final fk = _processForeignKeyAnnotation(field, fkAnnotation);
          if (fk != null) foreignKeys.add(fk);
        }
        // Auto-detect foreign key (ends with Id or _id)
        else if (field.displayName.endsWith('Id') ||
            field.displayName.endsWith('_id')) {
          final refTable = _inferReferencedTable(field.displayName);
          foreignKeys.add(
            "ForeignKey(column: '${_toSnakeCase(field.displayName)}', referencedTable: '$refTable', referencedColumn: 'id')",
          );
        }
      }
    }

    final schemaItems = [...columns];
    if (foreignKeys.isNotEmpty) {
      schemaItems.add('// Foreign Keys');
      schemaItems.addAll(foreignKeys);
    }
    if (constraints.isNotEmpty) {
      schemaItems.add('// Constraints');
      schemaItems.addAll(constraints);
    }

    return schemaItems.join(',\n    ');
  }

  /// Process class-level constraint annotations
  void _processClassConstraints(
    ClassElement element,
    List<String> constraints,
    Set<String> fieldNames,
  ) {
    for (final annotation in element.metadata.annotations) {
      final annotationName = annotation.element?.enclosingElement?.name;

      if (annotationName == 'PrimaryKey') {
        final columns = _getAnnotationListValue(annotation, 'columns');
        if (columns != null) {
          final columnNames = columns
              .map((c) => "'${c.toStringValue()}'")
              .join(', ');
          final name = annotation
              .computeConstantValue()
              ?.getField('name')
              ?.toStringValue();
          constraints.add(
            "// PRIMARY KEY ($columnNames)${name != null ? ' CONSTRAINT $name' : ''}",
          );
        }
      } else if (annotationName == 'Unique') {
        final columns = _getAnnotationListValue(annotation, 'columns');
        if (columns != null && columns.isNotEmpty) {
          final columnNames = columns
              .map((c) => "'${c.toStringValue()}'")
              .join(', ');
          final name = annotation
              .computeConstantValue()
              ?.getField('name')
              ?.toStringValue();
          constraints.add(
            "// UNIQUE ($columnNames)${name != null ? ' CONSTRAINT $name' : ''}",
          );
        }
      }
    }
  }

  /// Get a specific annotation from a field
  ElementAnnotation? _getFieldAnnotation(FieldElement field, String name) {
    return field.metadata.annotations.firstWhereOrNull(
      (a) => a.element?.enclosingElement?.name == name,
    );
  }

  /// Process ForeignKeyConstraint annotation
  String? _processForeignKeyAnnotation(
    FieldElement field,
    ElementAnnotation annotation,
  ) {
    final value = annotation.computeConstantValue();
    if (value == null) return null;

    final column =
        value.getField('column')?.toStringValue() ??
        _toSnakeCase(field.displayName);
    final referencedTable = value.getField('referencedTable')?.toStringValue();
    final referencedColumn =
        value.getField('referencedColumn')?.toStringValue() ?? 'id';

    if (referencedTable == null) return null;

    return "ForeignKey(column: '$column', referencedTable: '$referencedTable', referencedColumn: '$referencedColumn')";
  }

  /// Check if a field has a relationship annotation
  bool _isRelationshipField(FieldElement field) {
    return _hasAnnotation(field, 'OneToOne') ||
        _hasAnnotation(field, 'OneToMany') ||
        _hasAnnotation(field, 'ManyToMany');
  }

  /// Check if a field has a specific annotation
  bool _hasAnnotation(FieldElement field, String annotationName) {
    return field.metadata.annotations.firstWhereOrNull(
          (a) => a.element?.enclosingElement?.name == annotationName,
        ) !=
        null;
  }

  String? _readColumnAnnotation(FieldElement field, Set<String> fieldNames) {
    final isUnique = _hasAnnotation(field, 'Unique');
    final isId = _hasAnnotation(field, 'Id');

    return '''ColumnSchema(
      name: '${_toSnakeCase(field.displayName)}',
      type: '${_getDartToSqlType(field.type)}',
      nullable: ${!isId && field.type.nullabilitySuffix.toString().contains('question')},
      primaryKey: $isId,
      unique: $isUnique,
    )''';
  }

  String _getDartToSqlType(DartType type) {
    final name = type.getDisplayString(withNullability: false);
    const typeMap = {
      'String': 'TEXT',
      'int': 'INTEGER',
      'double': 'REAL',
      'bool': 'INTEGER',
      'DateTime': 'TIMESTAMP',
    };
    return typeMap[name] ?? 'TEXT';
  }

  String _toTableName(String className) {
    return _toSnakeCase(className);
  }

  String _toSnakeCase(String text) {
    return text
        .replaceAllMapped(
          RegExp('[A-Z]'),
          (m) => '_${m.group(0)!.toLowerCase()}',
        )
        .replaceFirst(RegExp('^_'), '');
  }

  String _toCamelCase(String text) {
    return text[0].toLowerCase() + text.substring(1);
  }

  String _inferReferencedTable(String fieldName) {
    // Remove 'Id' or '_id' suffix and convert to table name
    String tableName = fieldName;
    if (tableName.endsWith('Id')) {
      tableName = tableName.substring(0, tableName.length - 2);
    } else if (tableName.endsWith('_id')) {
      tableName = tableName.substring(0, tableName.length - 3);
    }
    return '${_toSnakeCase(tableName)}s'; // Pluralize
  }
}

Builder schemaGeneratorBuilder(BuilderOptions options) =>
    PartBuilder([SchemaGenerator()], '.schema.g.dart');
