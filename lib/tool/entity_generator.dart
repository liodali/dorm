import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:collection/collection.dart';
import 'package:dorm/src/annotation.dart';
import 'package:dorm/src/database/database_connection.dart';
import 'package:source_gen/source_gen.dart';

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
    final dbType = _getDatabaseType(annotation);

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
      final manyToMany = _getAnnotation(field, 'ManyToMany');

      if (oneToOne != null || oneToMany != null || manyToMany != null) {
        relationships.add({
          'fieldName': field.name,
          'type': _getRelationType(field),
          'annotation': oneToOne ?? oneToMany ?? manyToMany,
        });
        continue;
      }

      // Process all fields that are not relationships or ignored
      final columnName = _getColumnName(field, columnAnnotation);
      final sqlType = _getSqlType(field.type, dbType, columnAnnotation);
      final isPrimaryKey =
          idAnnotation != null ||
          (columnAnnotation != null && _isPrimaryKey(columnAnnotation));

      fields.add({
        'name': field.name,
        'type': field.type.getDisplayString(withNullability: true),
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

  ElementAnnotation? _getAnnotation(FieldElement field, String name) {
    return field.metadata.annotations.firstWhereOrNull(
      (a) => a.element?.enclosingElement?.name == name,
    );
  }

  String _getRelationType(FieldElement field) {
    final displayString = field.type.getDisplayString(withNullability: true);
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

    // Calculate relative path for part of directive
    final entityFileName = _getEntityFileName(sourceFilePath);

    return '''
// GENERATED CODE - DO NOT MODIFY BY HAND
// Generated code for $className

part of '$entityFileName';

class ${className}Repository extends Repository<$className> {
  ${className}Repository() : super('$tableName');

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

$manyToManyMethods

$findWithRelationsMethod
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

  DatabaseType _getDatabaseType(ConstantReader annotation) {
    final dbTypeValue = annotation.peek('dbType')?.objectValue;
    if (dbTypeValue != null) {
      final index = dbTypeValue.getField('index')?.toIntValue();
      if (index != null && index < DatabaseType.values.length) {
        return DatabaseType.values[index];
      }
    }
    return DatabaseType.postgresql;
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
    final typeName = dartType.getDisplayString(withNullability: false);

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
      'double': 'DOUBLE PRECISION',
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
        // Check if isOwning to determine direction
        final isOwning = _extractIsOwning(annotation);
        relationshipType = isOwning ? 'OneToMany_Owning' : 'OneToMany_Inverse';
      } else if (annotation.element?.enclosingElement?.name == 'ManyToMany') {
        relationshipType = 'ManyToMany';
      }

      if (relationshipType == null) continue;

      final caseCode = _generateRelationshipCase(
        fieldName,
        type,
        relationshipType,
        annotation,
        tableName,
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
  ) {
    final targetEntity = _extractTargetEntity(annotation);
    final joinTableInfo = _extractJoinTableInfo(
      annotation,
      ownerTableName,
      targetEntity,
    );

    if (relationshipType == 'OneToOne_Inverse') {
      // Inverse side - load single related entity by querying target table
      final foreignKey = '${_snakeCase(ownerTableName)}_id';
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
    } else if (relationshipType == 'OneToMany_Inverse') {
      // Inverse side (the "one" side) - load many related entities
      final foreignKey =
          _extractForeignKeyName(annotation) ??
          '${_snakeCase(ownerTableName)}_id';
      return '''        case '$fieldName':
          // Load OneToMany (inverse) relationship for $fieldName
          final ${_toCamelCase(targetEntity)}Repo = ${targetEntity}Repository();
          ${_toCamelCase(targetEntity)}Repo.setConnection(connection);
          final ${fieldName}Data = await ${_toCamelCase(targetEntity)}Repo.query()
            .where('$foreignKey = @id', {'id': entity.id})
            .toList();
          // Note: Requires mutable entity or copyWith pattern to set entity.$fieldName
          break;''';
    } else if (relationshipType == 'OneToMany_Owning') {
      // Owning side (the "many" side) - load single related entity
      final foreignKeyField = _extractForeignKeyField(annotation, fieldName);
      return '''        case '$fieldName':
          // Load OneToMany (owning) relationship for $fieldName
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
    final targetTable = _snakeCase(targetEntity);

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

    return {
      'tableName': tableNameMatch?.group(1) ?? '${ownerTableName}_$targetTable',
      'joinColumn': joinColMatch?.group(1) ?? '${ownerTableName}_id',
      'inverseColumn': inverseColMatch?.group(1) ?? '${targetTable}_id',
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
    final match = RegExp(r'''foreignKey:\s*['"](\w+)['"]''').firstMatch(source);
    return match?.group(1);
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

      // Skip inverse side (mappedBy is set)
      if (mappedBy != null) continue;

      final joinTableInfo = _extractJoinTableInfo(
        annotation,
        tableName,
        targetEntity,
      );
      final joinTableName = joinTableInfo['tableName']!;
      final joinColumn = joinTableInfo['joinColumn']!;
      final inverseColumn = joinTableInfo['inverseColumn']!;
      final targetTable = _snakeCase(targetEntity);

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
      final isOwning = _extractIsOwning(annotation);

      if (isOwning) {
        // Owning side - get related entity by FK
        final foreignKeyField = _extractForeignKeyField(annotation, fieldName);
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
    final fkColumn = '${_extractForeignKeyName(annotation) ?? '${_snakeCase(targetEntity)}_id'}';
    final sql = "UPDATE $tableName SET \$fkColumn = @targetId WHERE id = @ownerId";
    await connection.execute(sql, parameters: {
      'ownerId': ${_toCamelCase(className)}Id,
      'targetId': ${_toCamelCase(targetEntity)}Id,
    });
  }''');
      } else {
        // Inverse side - get related entity by querying target table
        final foreignKey = '${_snakeCase(className)}_id';
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

  /// Generate findWithRelations method for eager loading
  String _generateFindWithRelationsMethod(
    String className,
    String tableName,
    List<Map<String, dynamic>> relationships,
  ) {
    if (relationships.isEmpty) {
      return '';
    }

    final manyToManyRels = relationships.where((rel) {
      final annotation = rel['annotation'];
      return annotation.element?.enclosingElement?.name == 'ManyToMany' &&
          _extractMappedBy(annotation) == null;
    }).toList();

    if (manyToManyRels.isEmpty) {
      return '';
    }

    final relLoaders = manyToManyRels
        .map((rel) {
          final fieldName = rel['fieldName'];
          return '''
      if (includes.contains('$fieldName')) {
        final ${fieldName}Data = await get${_toPascalCase(fieldName)}(entity.id!);
        relatedData['$fieldName'] = ${fieldName}Data;
      }''';
        })
        .join('\n');

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
$relLoaders
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
${relLoaders.replaceAll('entity.id!', 'entity.id!')}
      results.add(relatedData);
    }

    return results;
  }''';
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
