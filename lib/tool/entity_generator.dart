import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart'
    show NullabilitySuffix;
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:collection/collection.dart';
import 'package:dormql/src/annotation.dart';
import 'package:dormql/src/database/database_connection.dart';
import 'package:source_gen/source_gen.dart';
import 'db_type_helper.dart';
import 'id_strategy_helper.dart'; // For ID strategy validation

class EntityGenerator extends GeneratorForAnnotation<Entity> {
  @override
  Future<String> generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) async {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@Entity can only be applied to classes',
        element: element,
      );
    }

    final className = element.name;
    final tableName =
        annotation.peek('tableName')?.stringValue ??
        _tableNameFromClass(className!);
    final dbType = DbTypeHelper.extractDbTypeFromElement(element);

    // Validate that @Id and @PrimaryKey are not used together
    _validatePrimaryKeyAnnotations(element);

    final fields = <Map<String, dynamic>>[];
    final relationships = <Map<String, dynamic>>[];

    for (final field in element.fields) {
      if (field.isStatic) continue;

      final ignoreAnnotation = _getAnnotation(field, 'Ignore');
      if (ignoreAnnotation != null) continue;

      final columnAnnotation = _getAnnotation(field, 'Column');
      final idAnnotation = _getAnnotation(field, 'Id');
      final oneToOne = _getAnnotation(field, 'OneToOne');
      final oneToMany = _getAnnotation(field, 'OneToMany');
      final manyToOne = _getAnnotation(field, 'ManyToOne');
      final manyToMany = _getAnnotation(field, 'ManyToMany');

      if (oneToOne != null ||
          oneToMany != null ||
          manyToOne != null ||
          manyToMany != null) {
        relationships.add({
          'fieldName': field.name,
          'type': _getRelationType(field),
          'annotation': oneToOne ?? oneToMany ?? manyToOne ?? manyToMany,
          'field':
              field, // Store field element to resolve target entity's tableName
        });
        continue;
      }

      // Validate @Id and @Column(primaryKey: true) conflict
      final conflictError = IdStrategyHelper.validateIdAndPrimaryKeyConflict(
        idAnnotation,
        columnAnnotation,
      );
      if (conflictError != null) {
        throw InvalidGenerationSourceError(
          conflictError,
          element: field,
        );
      }

      // Validate ID strategy if @Id is present
      if (idAnnotation != null) {
        final strategy = IdStrategyHelper.extractIdStrategy(idAnnotation);
        if (strategy != null) {
          final validationError = IdStrategyHelper.validateIdStrategyForType(
            strategy,
            field.type,
          );
          if (validationError != null) {
            throw InvalidGenerationSourceError(
              validationError,
              element: field,
            );
          }
        }

        // Validate nullable ID field
        final isNullable =
            field.type.nullabilitySuffix == NullabilitySuffix.question;
        final nullabilityError = IdStrategyHelper.validateIdNullability(
          idAnnotation,
          isNullable,
        );
        if (nullabilityError != null) {
          throw InvalidGenerationSourceError(
            nullabilityError,
            element: field,
          );
        }
      }

      // Process all fields that are not relationships or ignored
      final columnName = _getColumnName(field, columnAnnotation);
      final sqlType = _getSqlType(field.type, dbType, columnAnnotation);
      final isPrimaryKey =
          idAnnotation != null ||
          (columnAnnotation != null && _isPrimaryKey(columnAnnotation));

      fields.add({
        'name': field.name,
        'type': field.type.getDisplayString(),
        'columnName': columnName,
        'sqlType': sqlType,
        'isPrimaryKey': isPrimaryKey,
        'isNullable': field.type.nullabilitySuffix.toString().contains(
          'question',
        ),
        'column': columnAnnotation,
        'id': idAnnotation,
      });
    }

    // Get source file path for import calculation
    final sourceFilePath = buildStep.inputId.path;

    // Detect constructor parameters
    final constructorParams = _getConstructorParameters(element);

    final code = _generateRepositoryCode(
      className!,
      tableName,
      fields,
      relationships,
      dbType,
      sourceFilePath,
      constructorParams,
    );

    // Return the generated code
    return code;
  }

  /// Extract constructor parameters from the class
  Map<String, bool> _getConstructorParameters(ClassElement element) {
    final params = <String, bool>{}; // paramName -> isRequired

    // Get all non-static fields as they're likely constructor params
    for (final field in element.fields) {
      if (!field.isStatic) {
        // Check if field type is nullable
        final isNullable = field.type.nullabilitySuffix.toString().contains(
          'question',
        );
        params[field.displayName] =
            !isNullable; // Non-nullable fields are required
      }
    }

    return params;
  }

  String _tableNameFromClass(String className) {
    return RegExp(
      '[A-Z]',
    ).allMatches(className).map((m) => m.group(0)!.toLowerCase()).join('_');
  }

  /// Validate that @Id and @PrimaryKey annotations are not used together.
  /// @Id is for single-field primary keys, @PrimaryKey is for composite keys.
  void _validatePrimaryKeyAnnotations(ClassElement element) {
    // Check for @PrimaryKey on the class
    final hasPrimaryKeyAnnotation = element.metadata.annotations.any(
      (a) => a.element?.enclosingElement?.name == 'PrimaryKey',
    );

    // Check for @Id on any field
    bool hasIdAnnotation = false;
    for (final field in element.fields) {
      if (field.isStatic) continue;
      if (field.metadata.annotations.any(
        (a) => a.element?.enclosingElement?.name == 'Id',
      )) {
        hasIdAnnotation = true;
        break;
      }
    }

    if (hasPrimaryKeyAnnotation && hasIdAnnotation) {
      throw InvalidGenerationSourceError(
        'Cannot use both @Id and @PrimaryKey in the same entity. '
        'Use @Id on a single field for simple primary keys, or '
        '@PrimaryKey on the class for composite primary keys (multiple columns).',
        element: element,
      );
    }
  }

  ElementAnnotation? _getAnnotation(FieldElement field, String name) {
    return field.metadata.annotations.firstWhereOrNull(
      (a) => a.element?.enclosingElement?.name == name,
    );
  }

  String _getRelationType(FieldElement field) {
    final displayString = field.type.getDisplayString();
    if (displayString.contains('List')) return 'list';
    return 'single';
  }

  String _generateRepositoryCode(
    String className,
    String tableName,
    List<Map<String, dynamic>> fields,
    List<Map<String, dynamic>> relationships,
    DatabaseType dbType,
    String sourceFilePath,
    Map<String, bool> constructorParams,
  ) {
    // Find primary key field
    final primaryKeyField = fields.firstWhereOrNull(
      (f) => f['isPrimaryKey'] == true,
    );
    final primaryKeyColumn = primaryKeyField != null
        ? primaryKeyField['columnName'] as String
        : 'id';

    final fromRowMappings = fields
        .map((f) {
          final fieldName = f['name'];
          final columnName = f['columnName'];
          final dartType = f['type'];
          return "$fieldName: ${_generateTypeConversion(dartType, "row['$columnName']")}";
        })
        .join(',\n      ');

    final toRowMappings = fields
        .map((f) {
          final fieldName = f['name'];
          final columnName = f['columnName'];
          return "'$columnName': entity.$fieldName";
        })
        .join(',\n      ');

    final loadRelationshipsMethod = _generateLoadRelationshipsMethod(
      className,
      tableName,
      relationships,
    );

    // Generate OneToOne helper methods
    final oneToOneMethods = _generateOneToOneMethods(
      className,
      tableName,
      relationships,
    );

    // Generate OneToMany helper methods
    final oneToManyMethods = _generateOneToManyMethods(
      className,
      tableName,
      relationships,
    );

    // Generate ManyToOne helper methods
    final manyToOneMethods = _generateManyToOneMethods(
      className,
      tableName,
      relationships,
    );

    // Generate ManyToMany helper methods
    final manyToManyMethods = _generateManyToManyMethods(
      className,
      tableName,
      relationships,
    );

    // Generate findWithRelations method
    final findWithRelationsMethod = _generateFindWithRelationsMethod(
      className,
      tableName,
      relationships,
    );

    // Generate convenient findByIdWith{Relation} methods
    final findByIdWithRelationMethods = _generateFindByIdWithRelationMethods(
      className,
      tableName,
      relationships,
    );

    // Calculate relative path for part of directive
    final entityFileName = _getEntityFileName(sourceFilePath);

    // Generate Columns class
    final columnsClass = _generateColumnsClass(className, tableName, fields);

    return '''
// GENERATED CODE - DO NOT MODIFY BY HAND
// Generated code for $className

part of '$entityFileName';

$columnsClass

/// Extension to add columns getter to entity
extension ${className}Extension on $className {
  ${className}Columns get columns => const ${className}Columns._();
}

class ${className}Repository extends Repository<$className> {
  ${className}Repository() : super(
    '$tableName',
    primaryKeyColumn: '$primaryKeyColumn',
    autoIncrementPrimaryKey: true,
  );

  @override
  $className fromRow(Map<String, dynamic> row) {
    return $className(
      $fromRowMappings
    );
  }

  @override
  Map<String, dynamic> toRow($className entity) {
    return {
      $toRowMappings
    };
  }

$loadRelationshipsMethod

$oneToOneMethods

$oneToManyMethods

$manyToOneMethods

$manyToManyMethods

$findWithRelationsMethod

$findByIdWithRelationMethods
}
    ''';
  }

  /// Get the entity file name for the part of directive
  String _getEntityFileName(String sourceFilePath) {
    // Source file: lib/src/models/user_entity.dart
    // Generated file: lib/src/models/user_entity.orm.g.dart (same directory)
    // part of should be: 'user_entity.dart'
    return sourceFilePath.split('/').last;
  }

  String _getColumnName(FieldElement field, ElementAnnotation? annotation) {
    if (annotation != null) {
      // Parse @Column annotation to extract custom name
      final source = annotation.toSource();
      final nameMatch = RegExp(
        r'''name:\s*['"]([\w_]+)['"]''',
      ).firstMatch(source);
      if (nameMatch != null) {
        return nameMatch.group(1)!;
      }
    }
    // Convert camelCase to snake_case if no custom name specified
    return _snakeCase(field.displayName);
  }

  bool _isPrimaryKey(ElementAnnotation annotation) {
    // Simplified check - in real implementation, parse annotation properly
    return false;
  }

  String _getSqlType(
    DartType dartType,
    DatabaseType dbType,
    ElementAnnotation? columnAnnotation,
  ) {
    // Remove nullability suffix to get base type
    final typeName = dartType.getDisplayString().replaceAll('?', '');

    switch (dbType) {
      case DatabaseType.postgresql:
        return _getPostgreSQLType(typeName);
      case DatabaseType.mysql:
        return _getMySQLType(typeName);
      case DatabaseType.sqlite:
        return _getSQLiteType(typeName);
    }
  }

  String _getPostgreSQLType(String dartType) {
    const typeMap = {
      'String': 'TEXT',
      'int': 'INTEGER',
      'double': 'REAL',
      'num': 'REAL',
      'Long': 'REAL',
      'bool': 'BOOLEAN',
      'DateTime': 'TIMESTAMP',
      'List<int>': 'BYTEA',
    };
    return typeMap[dartType] ?? 'TEXT';
  }

  String _getMySQLType(String dartType) {
    const typeMap = {
      'String': 'VARCHAR(255)',
      'int': 'INT',
      'double': 'DOUBLE',
      'num': 'DOUBLE',
      'Long': 'DOUBLE',
      'bool': 'TINYINT(1)',
      'DateTime': 'DATETIME',
      'List<int>': 'BLOB',
    };
    return typeMap[dartType] ?? 'VARCHAR(255)';
  }

  String _getSQLiteType(String dartType) {
    const typeMap = {
      'String': 'TEXT',
      'int': 'INTEGER',
      'double': 'REAL',
      'num': 'REAL',
      'Long': 'REAL',
      'bool': 'INTEGER',
      'DateTime': 'TEXT',
      'List<int>': 'BLOB',
    };
    return typeMap[dartType] ?? 'TEXT';
  }

  String _generateTypeConversion(String dartType, String value) {
    final cleanType = dartType.replaceAll('?', '');
    final isNullable = dartType.contains('?');

    String conversion;
    switch (cleanType) {
      case 'int':
        conversion = '$value as int';
        break;
      case 'double':
        conversion = '($value as num).toDouble()';
        break;
      case 'bool':
        conversion = '$value as bool';
        break;
      case 'String':
        conversion = '$value as String';
        break;
      case 'DateTime':
        conversion = 'DateTime.parse($value as String)';
        break;
      default:
        conversion = value;
    }

    if (isNullable) {
      return '$value != null ? $conversion : null';
    }
    return conversion;
  }

  String _snakeCase(String text) {
    return text
        .replaceAllMapped(
          RegExp('[A-Z]'),
          (m) => '_${m.group(0)!.toLowerCase()}',
        )
        .replaceFirst(RegExp('^_'), '');
  }

  String _generateLoadRelationshipsMethod(
    String className,
    String tableName,
    List<Map<String, dynamic>> relationships,
  ) {
    if (relationships.isEmpty) {
      return '  @override\n  Future<void> loadRelationships($className entity, List<String> includes) async {\n    // No relationships defined\n  }';
    }

    final cases = <String>[];

    for (final rel in relationships) {
      final fieldName = rel['fieldName'];
      final type = rel['type'];
      final annotation = rel['annotation'];

      // Determine relationship type
      String? relationshipType;
      if (annotation.element?.enclosingElement?.name == 'OneToOne') {
        final isOwning = _extractIsOwning(annotation);
        relationshipType = isOwning ? 'OneToOne_Owning' : 'OneToOne_Inverse';
      } else if (annotation.element?.enclosingElement?.name == 'OneToMany') {
        // OneToMany is the owning side (FK is in target table)
        relationshipType = 'OneToMany';
      } else if (annotation.element?.enclosingElement?.name == 'ManyToOne') {
        // ManyToOne is always the owning side (the "many" side with FK)
        relationshipType = 'ManyToOne';
      } else if (annotation.element?.enclosingElement?.name == 'ManyToMany') {
        // Only owning side (no mappedBy) gets relationship loading
        final mappedBy = _extractMappedBy(annotation);
        if (mappedBy != null) continue; // Skip inverse side
        relationshipType = 'ManyToMany';
      }

      if (relationshipType == null) continue;

      final field = rel['field'] as FieldElement;
      final caseCode = _generateRelationshipCase(
        fieldName,
        type,
        relationshipType,
        annotation,
        tableName,
        className,
        field,
      );
      cases.add(caseCode);
    }

    return '''
  @override
  Future<void> loadRelationships($className entity, List<String> includes) async {
    for (final include in includes) {
      switch (include) {
${cases.join('\n')}
        default:
          throw Exception('Unknown relationship: \$include');
      }
    }
  }''';
  }

  String _generateRelationshipCase(
    String fieldName,
    String type,
    String relationshipType,
    ElementAnnotation annotation,
    String ownerTableName,
    String ownerClassName,
    FieldElement field,
  ) {
    final targetEntity = _extractTargetEntity(annotation);
    final joinTableInfo = _extractJoinTableInfo(
      annotation,
      ownerTableName,
      targetEntity,
    );

    if (relationshipType == 'OneToOne_Inverse') {
      // Inverse side - load single related entity by querying target table
      // Get FK from target entity's @ManyToOne or @OneToOne annotation
      final foreignKey = _extractForeignKeyFromTargetEntity(
        field,
        ownerClassName,
      );
      if (foreignKey == null) {
        throw InvalidGenerationSourceError(
          'OneToOne inverse relationship "$fieldName" requires the target entity "$targetEntity" '
          'to have a @OneToOne or @ManyToOne annotation with foreignKey pointing to "$ownerClassName".',
          element: field,
        );
      }
      return '''        case '$fieldName':
          // Load OneToOne (inverse) relationship for $fieldName
          final ${_toCamelCase(targetEntity)}Repo = ${targetEntity}Repository();
          ${_toCamelCase(targetEntity)}Repo.setConnection(connection);
          final ${fieldName}Results = await ${_toCamelCase(targetEntity)}Repo.query()
            .where('$foreignKey = @id', {'id': entity.id})
            .toList();
          final ${fieldName}Data = ${fieldName}Results.isNotEmpty ? ${fieldName}Results.first : null;
          // Note: Requires mutable entity or copyWith pattern to set entity.$fieldName
          break;''';
    } else if (relationshipType == 'OneToOne_Owning') {
      // Owning side - load single related entity by FK
      final foreignKeyField = _extractForeignKeyField(annotation, fieldName);
      return '''        case '$fieldName':
          // Load OneToOne (owning) relationship for $fieldName
          final ${_toCamelCase(targetEntity)}Repo = ${targetEntity}Repository();
          ${_toCamelCase(targetEntity)}Repo.setConnection(connection);
          final ${fieldName}Data = await ${_toCamelCase(targetEntity)}Repo.findById(entity.$foreignKeyField);
          // Note: Requires mutable entity or copyWith pattern to set entity.$fieldName
          break;''';
    } else if (relationshipType == 'OneToMany') {
      // OneToMany - load many related entities from target table
      // Use explicit foreignKey from annotation, or get from target entity's @ManyToOne
      final explicitForeignKey = _extractForeignKeyName(annotation);
      final targetForeignKey = _extractForeignKeyFromTargetEntity(
        field,
        ownerClassName,
      );
      final foreignKey = explicitForeignKey ?? targetForeignKey;
      if (foreignKey == null) {
        throw InvalidGenerationSourceError(
          'OneToMany relationship "$fieldName" requires either:\n'
          '  1. A foreignKey parameter in @OneToMany, OR\n'
          '  2. The target entity "$targetEntity" must have a @ManyToOne annotation '
          'with foreignKey pointing to "$ownerClassName".',
          element: field,
        );
      }
      return '''        case '$fieldName':
          // Load OneToMany relationship for $fieldName
          final ${_toCamelCase(targetEntity)}Repo = ${targetEntity}Repository();
          ${_toCamelCase(targetEntity)}Repo.setConnection(connection);
          final ${fieldName}Data = await ${_toCamelCase(targetEntity)}Repo.query()
            .where('$foreignKey = @id', {'id': entity.id})
            .toList();
          // Note: Requires mutable entity or copyWith pattern to set entity.$fieldName
          break;''';
    } else if (relationshipType == 'ManyToOne') {
      // ManyToOne - load single related entity by FK
      final foreignKeyField = _extractForeignKeyField(annotation, fieldName);
      return '''        case '$fieldName':
          // Load ManyToOne relationship for $fieldName
          final ${_toCamelCase(targetEntity)}Repo = ${targetEntity}Repository();
          ${_toCamelCase(targetEntity)}Repo.setConnection(connection);
          final ${fieldName}Data = await ${_toCamelCase(targetEntity)}Repo.findById(entity.$foreignKeyField);
          // Note: Requires mutable entity or copyWith pattern to set entity.$fieldName
          break;''';
    } else if (relationshipType == 'ManyToMany') {
      final joinTableName = joinTableInfo['tableName']!;
      return '''        case '$fieldName':
          // Load ManyToMany relationship for $fieldName via junction table $joinTableName
          final ${fieldName}Data = await get${_toPascalCase(fieldName)}(entity.id!);
          // Note: Requires mutable entity or copyWith pattern to set entity.$fieldName
          break;''';
    }

    return '';
  }

  /// Extract JoinTable info from ManyToMany annotation
  Map<String, String> _extractJoinTableInfo(
    ElementAnnotation annotation,
    String ownerTableName,
    String targetEntity,
  ) {
    final source = annotation.toSource();
    final targetTableFallback = _snakeCase(targetEntity);

    // Try to extract from JoinTable annotation
    final tableNameMatch = RegExp(
      r'''name:\s*['"](\w+)['"]''',
    ).firstMatch(source);
    final joinColMatch = RegExp(
      r'''joinColumn:\s*JoinColumn\s*\([^)]*name:\s*['"](\w+)['"]''',
    ).firstMatch(source);
    final inverseColMatch = RegExp(
      r'''inverseJoinColumn:\s*JoinColumn\s*\([^)]*name:\s*['"](\w+)['"]''',
    ).firstMatch(source);

    // Derive target table from inverseJoinColumn name (e.g., 'products_id' -> 'products')
    final inverseColumn =
        inverseColMatch?.group(1) ?? '${targetTableFallback}_id';
    final targetTable = inverseColumn.endsWith('_id')
        ? inverseColumn.substring(0, inverseColumn.length - 3)
        : targetTableFallback;

    return {
      'tableName': tableNameMatch?.group(1) ?? '${ownerTableName}_$targetTable',
      'joinColumn': joinColMatch?.group(1) ?? '${ownerTableName}_id',
      'inverseColumn': inverseColumn,
      'targetTable': targetTable,
    };
  }

  String _extractTargetEntity(ElementAnnotation annotation) {
    final source = annotation.toSource();
    final match = RegExp(r'targetEntity:\s*(\w+)').firstMatch(source);
    return match?.group(1) ?? 'Unknown';
  }

  String? _extractMappedBy(ElementAnnotation annotation) {
    final source = annotation.toSource();
    final match = RegExp(r'''mappedBy:\s*['"](\w+)['"]''').firstMatch(source);
    return match?.group(1);
  }

  /// Check if OneToMany annotation has isOwning: true
  bool _extractIsOwning(ElementAnnotation annotation) {
    final source = annotation.toSource();
    final match = RegExp(r'isOwning:\s*(true|false)').firstMatch(source);
    return match?.group(1) == 'true';
  }

  /// Extract foreignKey column name from annotation
  String? _extractForeignKeyName(ElementAnnotation annotation) {
    final source = annotation.toSource();
    final match = RegExp(
      r'''foreignKey:\s*['"]([\w_]+)['"]''',
    ).firstMatch(source);
    return match?.group(1);
  }

  /// Extract foreignKey from target entity's @ManyToOne or @OneToOne annotation that points back to the owner
  /// Returns null if no matching annotation with foreignKey is found
  String? _extractForeignKeyFromTargetEntity(
    FieldElement field,
    String ownerClassName,
  ) {
    // Get the field's type - for List<T>, extract T
    DartType fieldType = field.type;

    // Handle List<TargetEntity> type
    if (fieldType.isDartCoreList) {
      final listType = fieldType as InterfaceType;
      if (listType.typeArguments.isNotEmpty) {
        fieldType = listType.typeArguments.first;
      }
    }

    // Get the class element from the type
    final typeElement = fieldType.element;
    if (typeElement is ClassElement) {
      // Look for @ManyToOne or @OneToOne annotation on target entity's fields that points to owner
      for (final targetField in typeElement.fields) {
        if (targetField.isStatic) continue;

        for (final annotation in targetField.metadata.annotations) {
          final annotationName = annotation.element?.enclosingElement?.name;
          if (annotationName == 'ManyToOne' || annotationName == 'OneToOne') {
            final source = annotation.toSource();
            // Check if this annotation points to the owner entity
            final targetEntityMatch = RegExp(
              r'targetEntity:\s*(\w+)',
            ).firstMatch(source);
            if (targetEntityMatch != null &&
                targetEntityMatch.group(1) == ownerClassName) {
              // Found matching annotation, extract its foreignKey
              final fkMatch = RegExp(
                r'''foreignKey:\s*['"]([\w_]+)['"]''',
              ).firstMatch(source);
              if (fkMatch != null) {
                return fkMatch.group(1);
              }
            }
          }
        }
      }
    }
    return null;
  }

  /// Extract tableName from target entity's @Entity annotation
  /// by resolving the field's type to get the target class element
  String _extractTargetTableName(
    FieldElement field,
    String targetEntityClassName,
  ) {
    // Get the field's type - for List<T>, extract T
    DartType fieldType = field.type;

    // Handle List<TargetEntity> type
    if (fieldType.isDartCoreList) {
      final listType = fieldType as InterfaceType;
      if (listType.typeArguments.isNotEmpty) {
        fieldType = listType.typeArguments.first;
      }
    }

    // Get the class element from the type
    final typeElement = fieldType.element;
    if (typeElement is ClassElement) {
      // Look for @Entity annotation on the target class
      for (final annotation in typeElement.metadata.annotations) {
        if (annotation.element?.enclosingElement?.name == 'Entity') {
          final source = annotation.toSource();
          // Extract tableName from @Entity(tableName: 'xxx')
          final tableNameMatch = RegExp(
            r'''tableName:\s*['"]([\w_]+)['"]''',
          ).firstMatch(source);
          if (tableNameMatch != null) {
            return tableNameMatch.group(1)!;
          }
        }
      }
      // Fallback: derive table name from class name
      final className = typeElement.name;
      if (className != null) {
        return _snakeCase(className);
      }
    }

    // Fallback: derive from target entity class name
    return _snakeCase(targetEntityClassName);
  }

  /// Extract the Dart field name for the foreign key (e.g., userId for user_id)
  String _extractForeignKeyField(
    ElementAnnotation annotation,
    String fieldName,
  ) {
    final fkName = _extractForeignKeyName(annotation);
    if (fkName != null) {
      // Convert snake_case FK name to camelCase field name
      // e.g., user_id -> userId
      return fkName.replaceAllMapped(
        RegExp(r'_([a-z])'),
        (m) => m.group(1)!.toUpperCase(),
      );
    }
    // Default: fieldName + Id (e.g., user -> userId)
    return '${fieldName}Id';
  }

  String _toCamelCase(String text) {
    if (text.isEmpty) return text;
    return text[0].toLowerCase() + text.substring(1);
  }

  String _toPascalCase(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  /// Generate dedicated methods for ManyToMany relationships
  /// Only generates methods for the OWNING side (no mappedBy)
  /// The inverse side (with mappedBy) should NOT have these methods
  String _generateManyToManyMethods(
    String className,
    String tableName,
    List<Map<String, dynamic>> relationships,
  ) {
    final methods = <String>[];

    for (final rel in relationships) {
      final annotation = rel['annotation'];
      if (annotation.element?.enclosingElement?.name != 'ManyToMany') continue;

      final fieldName = rel['fieldName'];
      final targetEntity = _extractTargetEntity(annotation);
      final mappedBy = _extractMappedBy(annotation);

      // Skip inverse side (mappedBy is set) - only owning side gets methods
      if (mappedBy != null) {
        // Inverse side should NOT have getter methods
        // The relationship is managed from the owning side only
        continue;
      }

      final joinTableInfo = _extractJoinTableInfo(
        annotation,
        tableName,
        targetEntity,
      );
      final joinTableName = joinTableInfo['tableName']!;
      final joinColumn = joinTableInfo['joinColumn']!;
      final inverseColumn = joinTableInfo['inverseColumn']!;
      final targetTable = joinTableInfo['targetTable']!;

      // Generate get method for fetching related entities
      methods.add('''
  /// Get all ${targetEntity}s related to this $className via $joinTableName
  Future<List<$targetEntity>> get${_toPascalCase(fieldName)}(int ${_toCamelCase(className)}Id) async {
    final sql = """
      SELECT t.* 
      FROM $targetTable t 
      INNER JOIN $joinTableName jt ON t.id = jt.$inverseColumn 
      WHERE jt.$joinColumn = @id
    """;
    final results = await connection.query(sql, parameters: {'id': ${_toCamelCase(className)}Id});
    final repo = ${targetEntity}Repository();
    repo.setConnection(connection);
    return results.map((r) => repo.fromRow(r)).toList();
  }

  /// Add a $targetEntity to this $className's $fieldName
  Future<void> add${_toPascalCase(_singular(fieldName))}(int ${_toCamelCase(className)}Id, int ${_toCamelCase(targetEntity)}Id) async {
    final sql = "INSERT INTO $joinTableName ($joinColumn, $inverseColumn) VALUES (@ownerId, @targetId) ON CONFLICT DO NOTHING";
    await connection.execute(sql, parameters: {
      'ownerId': ${_toCamelCase(className)}Id,
      'targetId': ${_toCamelCase(targetEntity)}Id,
    });
  }

  /// Remove a $targetEntity from this $className's $fieldName
  Future<void> remove${_toPascalCase(_singular(fieldName))}(int ${_toCamelCase(className)}Id, int ${_toCamelCase(targetEntity)}Id) async {
    final sql = "DELETE FROM $joinTableName WHERE $joinColumn = @ownerId AND $inverseColumn = @targetId";
    await connection.execute(sql, parameters: {
      'ownerId': ${_toCamelCase(className)}Id,
      'targetId': ${_toCamelCase(targetEntity)}Id,
    });
  }

  /// Clear all ${targetEntity}s from this $className's $fieldName
  Future<void> clear${_toPascalCase(fieldName)}(int ${_toCamelCase(className)}Id) async {
    final sql = "DELETE FROM $joinTableName WHERE $joinColumn = @ownerId";
    await connection.execute(sql, parameters: {'ownerId': ${_toCamelCase(className)}Id});
  }

  /// Set the $fieldName for this $className (replaces all existing)
  Future<void> set${_toPascalCase(fieldName)}(int ${_toCamelCase(className)}Id, List<int> ${_toCamelCase(targetEntity)}Ids) async {
    await clear${_toPascalCase(fieldName)}(${_toCamelCase(className)}Id);
    for (final targetId in ${_toCamelCase(targetEntity)}Ids) {
      await add${_toPascalCase(_singular(fieldName))}(${_toCamelCase(className)}Id, targetId);
    }
  }''');
    }

    return methods.join('\n\n');
  }

  /// Generate dedicated methods for OneToOne relationships
  String _generateOneToOneMethods(
    String className,
    String tableName,
    List<Map<String, dynamic>> relationships,
  ) {
    final methods = <String>[];

    for (final rel in relationships) {
      final annotation = rel['annotation'];
      if (annotation.element?.enclosingElement?.name != 'OneToOne') continue;

      final fieldName = rel['fieldName'];
      final targetEntity = _extractTargetEntity(annotation);
      final field = rel['field'] as FieldElement;
      final isOwning = _extractIsOwning(annotation);

      if (isOwning) {
        // Owning side - get related entity by FK
        final foreignKeyField = _extractForeignKeyField(annotation, fieldName);
        final fkColumn = _extractForeignKeyName(annotation);
        if (fkColumn == null) {
          throw InvalidGenerationSourceError(
            'OneToOne owning relationship "$fieldName" requires a foreignKey parameter.',
            element: field,
          );
        }
        methods.add('''
  /// Get the $targetEntity for this $className
  Future<$targetEntity?> get${_toPascalCase(fieldName)}(int ${_toCamelCase(className)}Id) async {
    final entity = await findById(${_toCamelCase(className)}Id);
    if (entity == null || entity.$foreignKeyField == null) return null;
    final repo = ${targetEntity}Repository();
    repo.setConnection(connection);
    return await repo.findById(entity.$foreignKeyField!);
  }

  /// Set the $targetEntity for this $className
  Future<void> set${_toPascalCase(fieldName)}(int ${_toCamelCase(className)}Id, int? ${_toCamelCase(targetEntity)}Id) async {
    final sql = "UPDATE $tableName SET $fkColumn = @targetId WHERE id = @ownerId";
    await connection.execute(sql, parameters: {
      'ownerId': ${_toCamelCase(className)}Id,
      'targetId': ${_toCamelCase(targetEntity)}Id,
    });
  }''');
      } else {
        // Inverse side - get related entity by querying target table
        // Get FK from target entity's @ManyToOne or @OneToOne annotation
        final foreignKey = _extractForeignKeyFromTargetEntity(field, className);
        if (foreignKey == null) {
          throw InvalidGenerationSourceError(
            'OneToOne inverse relationship "$fieldName" requires the target entity "$targetEntity" '
            'to have a @OneToOne or @ManyToOne annotation with foreignKey pointing to "$className".',
            element: field,
          );
        }
        methods.add('''
  /// Get the $targetEntity for this $className
  Future<$targetEntity?> get${_toPascalCase(fieldName)}(int ${_toCamelCase(className)}Id) async {
    final repo = ${targetEntity}Repository();
    repo.setConnection(connection);
    final results = await repo.query()
      .where('$foreignKey = @id', {'id': ${_toCamelCase(className)}Id})
      .toList();
    return results.isNotEmpty ? results.first : null;
  }''');
      }
    }

    return methods.join('\n\n');
  }

  /// Generate dedicated methods for OneToMany relationships
  /// OneToMany is the owning side (FK is in target table)
  String _generateOneToManyMethods(
    String className,
    String tableName,
    List<Map<String, dynamic>> relationships,
  ) {
    final methods = <String>[];

    for (final rel in relationships) {
      final annotation = rel['annotation'];
      if (annotation.element?.enclosingElement?.name != 'OneToMany') continue;

      final fieldName = rel['fieldName'];
      final targetEntity = _extractTargetEntity(annotation);
      final field = rel['field'] as FieldElement;

      // OneToMany is the owning side - FK column is in target table
      // Use explicit foreignKey from annotation, or get from target entity's @ManyToOne
      final explicitForeignKey = _extractForeignKeyName(annotation);
      final targetForeignKey = _extractForeignKeyFromTargetEntity(
        field,
        className,
      );
      final foreignKey = explicitForeignKey ?? targetForeignKey;
      if (foreignKey == null) {
        throw InvalidGenerationSourceError(
          'OneToMany relationship "$fieldName" requires either:\n'
          '  1. A foreignKey parameter in @OneToMany, OR\n'
          '  2. The target entity "$targetEntity" must have a @ManyToOne annotation '
          'with foreignKey pointing to "$className".',
          element: field,
        );
      }

      // Get target table name from target entity's @Entity annotation
      final targetTable = _extractTargetTableName(field, targetEntity);

      methods.add('''
  /// Get all ${targetEntity}s for this $className
  Future<List<$targetEntity>> get${_toPascalCase(fieldName)}(int ${_toCamelCase(className)}Id) async {
    final repo = ${targetEntity}Repository();
    repo.setConnection(connection);
    return await repo.query()
      .where('$foreignKey = @id', {'id': ${_toCamelCase(className)}Id})
      .toList();
  }

  /// Add a $targetEntity to this $className's $fieldName
  Future<void> add${_toPascalCase(_singular(fieldName))}(int ${_toCamelCase(className)}Id, int ${_toCamelCase(targetEntity)}Id) async {
    final sql = "UPDATE $targetTable SET $foreignKey = @ownerId WHERE id = @targetId";
    await connection.execute(sql, parameters: {
      'ownerId': ${_toCamelCase(className)}Id,
      'targetId': ${_toCamelCase(targetEntity)}Id,
    });
  }

  /// Remove a $targetEntity from this $className's $fieldName
  Future<void> remove${_toPascalCase(_singular(fieldName))}(int ${_toCamelCase(targetEntity)}Id) async {
    final sql = "UPDATE $targetTable SET $foreignKey = NULL WHERE id = @targetId";
    await connection.execute(sql, parameters: {
      'targetId': ${_toCamelCase(targetEntity)}Id,
    });
  }

  /// Clear all ${targetEntity}s from this $className's $fieldName
  Future<void> clear${_toPascalCase(fieldName)}(int ${_toCamelCase(className)}Id) async {
    final sql = "UPDATE $targetTable SET $foreignKey = NULL WHERE $foreignKey = @ownerId";
    await connection.execute(sql, parameters: {'ownerId': ${_toCamelCase(className)}Id});
  }

  /// Set the $fieldName for this $className (replaces all existing)
  Future<void> set${_toPascalCase(fieldName)}(int ${_toCamelCase(className)}Id, List<int> ${_toCamelCase(targetEntity)}Ids) async {
    await clear${_toPascalCase(fieldName)}(${_toCamelCase(className)}Id);
    for (final targetId in ${_toCamelCase(targetEntity)}Ids) {
      await add${_toPascalCase(_singular(fieldName))}(${_toCamelCase(className)}Id, targetId);
    }
  }

  /// Get $className with $fieldName loaded
  Future<({$className entity, List<$targetEntity> $fieldName})?> get${className}With${_toPascalCase(fieldName)}(int ${_toCamelCase(className)}Id) async {
    final entity = await findById(${_toCamelCase(className)}Id);
    if (entity == null) return null;
    final ${fieldName}Data = await get${_toPascalCase(fieldName)}(${_toCamelCase(className)}Id);
    return (entity: entity, $fieldName: ${fieldName}Data);
  }

  /// Get all ${className}s with $fieldName loaded
  Future<List<({$className entity, List<$targetEntity> $fieldName})>> getAll${className}sWith${_toPascalCase(fieldName)}() async {
    final entities = await getAll();
    final results = <({$className entity, List<$targetEntity> $fieldName})>[];
    for (final entity in entities) {
      final ${fieldName}Data = await get${_toPascalCase(fieldName)}(entity.id!);
      results.add((entity: entity, $fieldName: ${fieldName}Data));
    }
    return results;
  }''');
    }

    return methods.join('\n\n');
  }

  /// Generate dedicated methods for ManyToOne relationships
  String _generateManyToOneMethods(
    String className,
    String tableName,
    List<Map<String, dynamic>> relationships,
  ) {
    final methods = <String>[];

    for (final rel in relationships) {
      final annotation = rel['annotation'];
      if (annotation.element?.enclosingElement?.name != 'ManyToOne') continue;

      final fieldName = rel['fieldName'];
      final targetEntity = _extractTargetEntity(annotation);
      final foreignKeyField = _extractForeignKeyField(annotation, fieldName);
      final foreignKeyColumn =
          _extractForeignKeyName(annotation) ??
          '${_snakeCase(targetEntity)}_id';

      // Generate get method for fetching the related entity
      methods.add('''
  /// Get the $targetEntity for this $className
  Future<$targetEntity?> get${_toPascalCase(fieldName)}(int ${_toCamelCase(className)}Id) async {
    final entity = await findById(${_toCamelCase(className)}Id);
    if (entity == null || entity.$foreignKeyField == null) return null;
    final repo = ${targetEntity}Repository();
    repo.setConnection(connection);
    return await repo.findById(entity.$foreignKeyField!);
  }

  /// Set the $targetEntity for this $className
  Future<void> set${_toPascalCase(fieldName)}(int ${_toCamelCase(className)}Id, int? ${_toCamelCase(targetEntity)}Id) async {
    final sql = "UPDATE $tableName SET $foreignKeyColumn = @targetId WHERE id = @ownerId";
    await connection.execute(sql, parameters: {
      'ownerId': ${_toCamelCase(className)}Id,
      'targetId': ${_toCamelCase(targetEntity)}Id,
    });
  }

  /// Get $className with $fieldName loaded
  Future<({$className entity, $targetEntity? $fieldName})?> get${className}With${_toPascalCase(fieldName)}(int ${_toCamelCase(className)}Id) async {
    final entity = await findById(${_toCamelCase(className)}Id);
    if (entity == null) return null;
    final ${fieldName}Data = await get${_toPascalCase(fieldName)}(${_toCamelCase(className)}Id);
    return (entity: entity, $fieldName: ${fieldName}Data);
  }''');
    }

    return methods.join('\n\n');
  }

  /// Generate findWithRelations method for eager loading
  String _generateFindWithRelationsMethod(
    String className,
    String tableName,
    List<Map<String, dynamic>> relationships,
  ) {
    if (relationships.isEmpty) {
      return '';
    }

    // Collect all relationship loaders
    final relLoaders = <String>[];

    for (final rel in relationships) {
      final annotation = rel['annotation'];
      final fieldName = rel['fieldName'];
      final annotationName = annotation.element?.enclosingElement?.name;

      // ManyToMany (only owning side - no mappedBy)
      if (annotationName == 'ManyToMany') {
        final mappedBy = _extractMappedBy(annotation);
        if (mappedBy != null) continue; // Skip inverse side

        relLoaders.add('''
      if (includes.contains('$fieldName')) {
        final ${fieldName}Data = await get${_toPascalCase(fieldName)}(entity.id!);
        relatedData['$fieldName'] = ${fieldName}Data;
      }''');
      }
      // OneToMany (always inverse side)
      else if (annotationName == 'OneToMany') {
        relLoaders.add('''
      if (includes.contains('$fieldName')) {
        final ${fieldName}Data = await get${_toPascalCase(fieldName)}(entity.id!);
        relatedData['$fieldName'] = ${fieldName}Data;
      }''');
      }
      // OneToOne
      else if (annotationName == 'OneToOne') {
        relLoaders.add('''
      if (includes.contains('$fieldName')) {
        final ${fieldName}Data = await get${_toPascalCase(fieldName)}(entity.id!);
        relatedData['$fieldName'] = ${fieldName}Data;
      }''');
      }
      // ManyToOne
      else if (annotationName == 'ManyToOne') {
        relLoaders.add('''
      if (includes.contains('$fieldName')) {
        final ${fieldName}Data = await get${_toPascalCase(fieldName)}(entity.id!);
        relatedData['$fieldName'] = ${fieldName}Data;
      }''');
      }
    }

    if (relLoaders.isEmpty) {
      return '';
    }

    final relLoadersCode = relLoaders.join('\n');

    return '''
  /// Find entity by ID with related data
  /// Returns a map with 'entity' and requested relation names as keys
  Future<Map<String, dynamic>?> findByIdWithRelations(
    int id, {
    List<String> includes = const [],
  }) async {
    final entity = await findById(id);
    if (entity == null) return null;

    final relatedData = <String, dynamic>{'entity': entity};
$relLoadersCode
    return relatedData;
  }

  /// Get all entities with related data
  /// Returns a list of maps with 'entity' and requested relation names as keys
  Future<List<Map<String, dynamic>>> getAllWithRelations({
    List<String> includes = const [],
  }) async {
    final entities = await getAll();
    final results = <Map<String, dynamic>>[];

    for (final entity in entities) {
      final relatedData = <String, dynamic>{'entity': entity};
$relLoadersCode
      results.add(relatedData);
    }

    return results;
  }''';
  }

  /// Generate convenient findByIdWith{Relation} methods for each relationship
  String _generateFindByIdWithRelationMethods(
    String className,
    String tableName,
    List<Map<String, dynamic>> relationships,
  ) {
    if (relationships.isEmpty) {
      return '';
    }

    final methods = <String>[];

    for (final rel in relationships) {
      final annotation = rel['annotation'];
      final fieldName = rel['fieldName'];
      final targetEntity = _extractTargetEntity(annotation);
      final annotationName = annotation.element?.enclosingElement?.name;
      final mappedBy = _extractMappedBy(annotation);
      final isOwning = _extractIsOwning(annotation);

      // ManyToMany (only owning side - no mappedBy)
      if (annotationName == 'ManyToMany') {
        if (mappedBy != null) continue; // Skip inverse side

        methods.add('''
  /// Find $className by ID with $fieldName loaded
  Future<({$className entity, List<$targetEntity> $fieldName})?> findByIdWith${_toPascalCase(fieldName)}(int id) async {
    final entity = await findById(id);
    if (entity == null) return null;
    final ${fieldName}Data = await get${_toPascalCase(fieldName)}(id);
    return (entity: entity, $fieldName: ${fieldName}Data);
  }''');
      }
      // OneToMany (inverse side)
      else if (annotationName == 'OneToMany' && mappedBy != null && !isOwning) {
        methods.add('''
  /// Find $className by ID with $fieldName loaded
  Future<({$className entity, List<$targetEntity> $fieldName})?> findByIdWith${_toPascalCase(fieldName)}(int id) async {
    final entity = await findById(id);
    if (entity == null) return null;
    final ${fieldName}Data = await get${_toPascalCase(fieldName)}(id);
    return (entity: entity, $fieldName: ${fieldName}Data);
  }''');
      }
      // OneToOne
      else if (annotationName == 'OneToOne') {
        methods.add('''
  /// Find $className by ID with $fieldName loaded
  Future<({$className entity, $targetEntity? $fieldName})?> findByIdWith${_toPascalCase(fieldName)}(int id) async {
    final entity = await findById(id);
    if (entity == null) return null;
    final ${fieldName}Data = await get${_toPascalCase(fieldName)}(id);
    return (entity: entity, $fieldName: ${fieldName}Data);
  }''');
      }
    }

    return methods.join('\n\n');
  }

  /// Convert plural to singular (simple implementation)
  String _singular(String text) {
    if (text.endsWith('ies')) {
      return '${text.substring(0, text.length - 3)}y';
    } else if (text.endsWith('es')) {
      return text.substring(0, text.length - 2);
    } else if (text.endsWith('s')) {
      return text.substring(0, text.length - 1);
    }
    return text;
  }

  /// Generate the Columns class for type-safe column references
  String _generateColumnsClass(
    String className,
    String tableName,
    List<Map<String, dynamic>> fields,
  ) {
    final columnGetters = fields.map((f) {
      return '''
  /// Column metadata for ${f['name']}
  ColumnMetadata get ${f['name']} => ColumnMetadata(
    fieldName: '${f['name']}',
    columnName: '${f['columnName']}',
    dartType: '${f['type']}',
    sqlType: '${f['sqlType']}',
    isPrimaryKey: ${f['isPrimaryKey']},
    isNullable: ${f['isNullable']},
    tableName: '$tableName',
  );''';
    }).join('\n\n');

    return '''
/// Type-safe column references for $className
class ${className}Columns {
  const ${className}Columns._();

$columnGetters

  /// Get all columns as a list
  List<ColumnMetadata> get all => [
${fields.map((f) => '      ${f['name']},').join('\n')}
  ];
}''';
  }
}

Builder entityGeneratorBuilder(BuilderOptions options) {
  return _CustomPathBuilder(
    EntityGenerator(),
    generatedExtension: '.orm.g.dart',
  );
}

/// Custom builder that outputs to lib/db_gen directory
class _CustomPathBuilder extends Builder {
  final GeneratorForAnnotation _generator;
  final String generatedExtension;

  _CustomPathBuilder(this._generator, {required this.generatedExtension});

  @override
  Map<String, List<String>> get buildExtensions {
    // Match any .dart file in lib/ and declare output pattern
    // Build runner will use this to know where to expect the output
    // return const {
    //   '.dart': [
    //     'db_gen/entities/{{}}.orm.g.dart',
    //   ],
    // };
    return const {
      'dart': ['orm.g.dart'],
    };
  }

  @override
  Future<void> build(BuildStep buildStep) async {
    final resolver = buildStep.resolver;
    if (!await resolver.isLibrary(buildStep.inputId)) return;

    final lib = await buildStep.inputLibrary;
    final generated = await _generator.generate(
      LibraryReader(lib),
      buildStep,
    );

    if (generated.isEmpty) return;

    // Build the output path based on buildExtensions pattern
    // Input: lib/src/models/post_entity.dart
    // Output: lib/src/models/post_entity.orm.g.dart (as declared in buildExtensions)
    final inputPath = buildStep.inputId.path;
    final outputPath = inputPath.replaceAll('.dart', generatedExtension);

    final outputId = AssetId(buildStep.inputId.package, outputPath);
    await buildStep.writeAsString(outputId, generated);
  }
}
