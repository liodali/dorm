import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:crypto/crypto.dart';
import 'package:dorm/src/annotation.dart';
import 'package:source_gen/source_gen.dart';

/// Generator for @Db annotation
/// Generates a database class with repository extensions
class DbGenerator extends GeneratorForAnnotation<Db> {
  @override
  Future<String> generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) async {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@Db can only be applied to classes',
        element: element,
      );
    }

    final className = element.name;
    final migrationVersion = annotation.peek('migrationVersion')?.intValue ?? 1;
    final dbName = annotation.peek('name')?.stringValue;
    final generateSql = annotation.peek('generateSql')?.boolValue ?? false;
    final sqlDialectValue = annotation.peek('sqlDialect')?.objectValue;

    // Extract DbConfig from annotation
    final configInfo = _extractDbConfig(annotation);

    // Determine SQL dialect
    String sqlDialect = 'postgresql';
    if (sqlDialectValue != null) {
      final dialectName = sqlDialectValue.getField('_name')?.toStringValue();
      if (dialectName != null) {
        sqlDialect = dialectName;
      }
    } else if (configInfo != null) {
      sqlDialect = configInfo.dbType;
    }

    // Extract entity types and their schema info from annotation
    final entitiesReader = annotation.peek('entities');
    final entities = <_EntityInfo>[];
    final manyToManyRelations = <_ManyToManyInfo>[];
    final entityElements = <String, ClassElement>{};
    final entityToTableName =
        <String, String>{}; // Map entity name to table name

    if (entitiesReader != null && !entitiesReader.isNull) {
      final entityList = entitiesReader.listValue;

      // First pass: collect all entity elements and their table names
      for (final entityValue in entityList) {
        final typeValue = entityValue.toTypeValue();
        if (typeValue != null) {
          final entityElement = typeValue.element;
          if (entityElement is ClassElement && entityElement.name != null) {
            entityElements[entityElement.name!] = entityElement;

            // Extract table name from @Entity annotation
            String tableName = _toSnakeCase(entityElement.name!);
            for (final meta in entityElement.metadata.annotations) {
              if (meta.element?.enclosingElement?.name == 'Entity') {
                final source = meta.toSource();
                final tableMatch = RegExp(
                  'tableName:\\s*[\'"]([\\w_]+)[\'"]',
                ).firstMatch(source);
                if (tableMatch != null) {
                  tableName = tableMatch.group(1)!;
                }
                break;
              }
            }
            entityToTableName[entityElement.name!] = tableName;
          }
        }
      }

      // Second pass: extract entity info and relationships
      for (final entityValue in entityList) {
        final typeValue = entityValue.toTypeValue();
        if (typeValue != null) {
          final entityElement = typeValue.element;
          if (entityElement is ClassElement && entityElement.name != null) {
            final tableName = entityToTableName[entityElement.name!]!;

            // Extract fields/columns from entity
            final columns = _extractColumnsFromEntity(entityElement);

            // Extract ManyToMany relationships
            final m2mRelations = _extractManyToManyRelations(
              entityElement,
              tableName,
              entityElements,
              entityToTableName,
            );
            manyToManyRelations.addAll(m2mRelations);

            entities.add(
              _EntityInfo(
                className: entityElement.name!,
                repositoryName: '${entityElement.name}Repository',
                tableName: tableName,
                columns: columns,
              ),
            );
          }
        }
      }
    }

    // Validate ManyToMany relationships
    final validationErrors = _validateManyToManyRelations(
      manyToManyRelations,
      entityElements,
    );
    if (validationErrors.isNotEmpty) {
      throw InvalidGenerationSourceError(
        'ManyToMany configuration errors:\n${validationErrors.join('\n')}',
        element: element,
      );
    }

    // Deduplicate junction tables (keep only owning side)
    final junctionTables = _deduplicateJunctionTables(
      manyToManyRelations,
      entityToTableName,
    );

    // Generate schema hash to detect changes (include junction tables)
    final schemaHash = _generateSchemaHash(entities, junctionTables);

    // Generate SQL file if requested
    if (generateSql) {
      await _generateSqlFile(
        buildStep: buildStep,
        dbName: dbName ?? className!.toLowerCase(),
        entities: entities,
        junctionTables: junctionTables,
        sqlDialect: sqlDialect,
        migrationVersion: migrationVersion,
      );
    }

    return _generateDbCode(
      className: className!,
      entities: entities,
      junctionTables: junctionTables,
      migrationVersion: migrationVersion,
      configInfo: configInfo,
      dbName: dbName,
      schemaHash: schemaHash,
    );
  }

  /// Generate SQL file with CREATE TABLE statements
  Future<void> _generateSqlFile({
    required BuildStep buildStep,
    required String dbName,
    required List<_EntityInfo> entities,
    required List<_JunctionTableInfo> junctionTables,
    required String sqlDialect,
    required int migrationVersion,
  }) async {
    final buffer = StringBuffer();
    final timestamp = DateTime.now().toIso8601String();

    // Header
    buffer.writeln(
      '-- ============================================================',
    );
    buffer.writeln('-- Database: $dbName');
    buffer.writeln('-- Generated: $timestamp');
    buffer.writeln('-- Migration Version: $migrationVersion');
    buffer.writeln('-- SQL Dialect: $sqlDialect');
    buffer.writeln(
      '-- ============================================================',
    );
    buffer.writeln();

    // Entity tables
    buffer.writeln('-- Entity Tables');
    buffer.writeln(
      '-- ============================================================',
    );
    buffer.writeln();

    for (final entity in entities) {
      buffer.writeln('-- Table: ${entity.tableName}');
      buffer.writeln(_generateCreateTableSql(entity, sqlDialect));
      buffer.writeln();
    }

    // Junction tables
    if (junctionTables.isNotEmpty) {
      buffer.writeln('-- Junction Tables (ManyToMany)');
      buffer.writeln(
        '-- ============================================================',
      );
      buffer.writeln();

      for (final junction in junctionTables) {
        buffer.writeln('-- Junction: ${junction.tableName}');
        buffer.writeln(_generateJunctionTableSql(junction, sqlDialect));
        buffer.writeln();
      }
    }

    // Write to .dart_tool/dorm/<db_name>.sql
    final sqlDir = Directory('.dart_tool/dorm');
    if (!sqlDir.existsSync()) {
      sqlDir.createSync(recursive: true);
    }

    final sqlFile = File('${sqlDir.path}/$dbName.sql');
    sqlFile.writeAsStringSync(buffer.toString());

    // Also write a versioned copy
    final versionedFile = File(
      '${sqlDir.path}/${dbName}_v$migrationVersion.sql',
    );
    versionedFile.writeAsStringSync(buffer.toString());
  }

  /// Generate CREATE TABLE SQL for an entity
  String _generateCreateTableSql(_EntityInfo entity, String dialect) {
    final buffer = StringBuffer();
    buffer.writeln('CREATE TABLE IF NOT EXISTS ${entity.tableName} (');

    final columnDefs = <String>[];

    for (final column in entity.columns) {
      final parts = <String>[];
      parts.add('  ${column.name}');

      // Handle auto-increment for primary key
      if (column.isPrimaryKey) {
        switch (dialect) {
          case 'postgresql':
            parts.add(column.sqlType == 'INTEGER' ? 'SERIAL' : 'BIGSERIAL');
            parts.add('PRIMARY KEY');
          case 'mysql':
            parts.add('${column.sqlType} AUTO_INCREMENT PRIMARY KEY');
          case 'sqlite':
            parts.add('INTEGER PRIMARY KEY AUTOINCREMENT');
          default:
            parts.add('${column.sqlType} PRIMARY KEY');
        }
      } else {
        parts.add(column.sqlType);
        if (!column.isNullable) {
          parts.add('NOT NULL');
        }
      }

      columnDefs.add(parts.join(' '));
    }

    buffer.writeln(columnDefs.join(',\n'));
    buffer.write(')');

    if (dialect == 'mysql') {
      buffer.write(' ENGINE=InnoDB');
    }

    buffer.writeln(';');

    return buffer.toString();
  }

  /// Generate CREATE TABLE SQL for a junction table
  String _generateJunctionTableSql(
    _JunctionTableInfo junction,
    String dialect,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('CREATE TABLE IF NOT EXISTS ${junction.tableName} (');

    final columnDefs = <String>[
      '  ${junction.joinColumnName} INTEGER NOT NULL',
      '  ${junction.inverseColumnName} INTEGER NOT NULL',
      '  PRIMARY KEY (${junction.joinColumnName}, ${junction.inverseColumnName})',
      '  FOREIGN KEY (${junction.joinColumnName}) REFERENCES ${junction.ownerTableName} (${junction.joinColumnRef}) ON DELETE CASCADE',
      '  FOREIGN KEY (${junction.inverseColumnName}) REFERENCES ${junction.targetTableName} (${junction.inverseColumnRef}) ON DELETE CASCADE',
    ];

    buffer.writeln(columnDefs.join(',\n'));
    buffer.write(')');

    if (dialect == 'mysql') {
      buffer.write(' ENGINE=InnoDB');
    }

    buffer.writeln(';');

    // Add indexes if needed
    if (junction.createIndex) {
      buffer.writeln();
      buffer.writeln(
        'CREATE INDEX IF NOT EXISTS idx_${junction.tableName}_${junction.joinColumnName} ON ${junction.tableName} (${junction.joinColumnName});',
      );
      buffer.writeln(
        'CREATE INDEX IF NOT EXISTS idx_${junction.tableName}_${junction.inverseColumnName} ON ${junction.tableName} (${junction.inverseColumnName});',
      );
    }

    return buffer.toString();
  }

  /// Extract ManyToMany relationships from entity
  List<_ManyToManyInfo> _extractManyToManyRelations(
    ClassElement element,
    String ownerTableName,
    Map<String, ClassElement> entityElements,
    Map<String, String> entityToTableName,
  ) {
    final relations = <_ManyToManyInfo>[];
    // Regex patterns for parsing annotations
    final targetEntityPattern = RegExp(r'targetEntity:\s*(\w+)');
    final mappedByPattern = RegExp(r'''mappedBy:\s*['"](\w+)['"]''');
    final joinTablePattern = RegExp(r'joinTable:\s*JoinTable');
    final namePattern = RegExp(r'''name:\s*['"](\w+)['"]''');
    final createIndexPattern = RegExp(r'createIndex:\s*(true|false)');

    for (final field in element.fields) {
      if (field.isStatic) continue;

      for (final meta in field.metadata.annotations) {
        if (meta.element?.enclosingElement?.name == 'ManyToMany') {
          final source = meta.toSource();

          // Extract targetEntity
          final targetMatch = targetEntityPattern.firstMatch(source);
          if (targetMatch == null) continue;
          final targetEntityName = targetMatch.group(1)!;

          // Check if this is the owning side (has joinTable) or inverse side (has mappedBy)
          final mappedByMatch = mappedByPattern.firstMatch(source);
          final hasJoinTable = joinTablePattern.hasMatch(source);
          final isOwningSide = hasJoinTable || mappedByMatch == null;

          if (isOwningSide && mappedByMatch == null) {
            // Owning side - extract or generate junction table config
            String joinTableName;
            String joinColumnName;
            String joinColumnRef;
            String inverseColumnName;
            String inverseColumnRef;
            bool createIndex = true;

            // Get target table name from map or fallback to snake_case
            final targetTableName =
                entityToTableName[targetEntityName] ??
                _toSnakeCase(targetEntityName);

            // Try to extract table name from annotation
            final nameMatch = namePattern.firstMatch(source);
            if (nameMatch != null) {
              joinTableName = nameMatch.group(1)!;
            } else {
              // Auto-generate junction table name
              joinTableName = '${ownerTableName}_$targetTableName';
            }

            // Default column names (can be customized via JoinColumn in annotation)
            joinColumnName = '${ownerTableName}_id';
            joinColumnRef = 'id';
            inverseColumnName = '${targetTableName}_id';
            inverseColumnRef = 'id';

            // Check createIndex
            final indexMatch = createIndexPattern.firstMatch(source);
            if (indexMatch != null) {
              createIndex = indexMatch.group(1) == 'true';
            }

            relations.add(
              _ManyToManyInfo(
                ownerEntityName: element.name!,
                ownerTableName: ownerTableName,
                targetEntityName: targetEntityName,
                fieldName: field.name!, // Fix null safety for field.name
                joinTableName: joinTableName,
                joinColumnName: joinColumnName,
                joinColumnRef: joinColumnRef,
                inverseColumnName: inverseColumnName,
                inverseColumnRef: inverseColumnRef,
                isOwningSide: true,
                createIndex: createIndex,
              ),
            );
          } else {
            // Inverse side (has mappedBy) - just record for validation
            relations.add(
              _ManyToManyInfo(
                ownerEntityName: element.name!,
                ownerTableName: ownerTableName,
                targetEntityName: targetEntityName,
                fieldName: field.name!,
                joinTableName: '',
                joinColumnName: '',
                joinColumnRef: '',
                inverseColumnName: '',
                inverseColumnRef: '',
                isOwningSide: false,
                mappedBy: mappedByMatch.group(1),
                createIndex: false,
              ),
            );
          }
        }
      }
    }

    return relations;
  }

  /// Validate ManyToMany relationships
  List<String> _validateManyToManyRelations(
    List<_ManyToManyInfo> relations,
    Map<String, ClassElement> entityElements,
  ) {
    final errors = <String>[];

    for (final relation in relations) {
      // Check target entity exists
      if (!entityElements.containsKey(relation.targetEntityName)) {
        errors.add(
          '${relation.ownerEntityName}.${relation.fieldName}: Target entity "${relation.targetEntityName}" not found in @Db entities list',
        );
        continue;
      }

      if (relation.isOwningSide) {
        // Owning side must have joinTable
        if (relation.joinTableName.isEmpty) {
          errors.add(
            '${relation.ownerEntityName}.${relation.fieldName}: Owning side must define joinTable',
          );
        }

        // Check if inverse side exists and references this field
        final inverseRelations = relations.where(
          (r) =>
              !r.isOwningSide &&
              r.ownerEntityName == relation.targetEntityName &&
              r.targetEntityName == relation.ownerEntityName,
        );

        if (inverseRelations.isEmpty) {
          // Warning: no inverse side defined (optional but recommended)
        } else {
          for (final inverse in inverseRelations) {
            if (inverse.mappedBy != relation.fieldName) {
              errors.add(
                '${inverse.ownerEntityName}.${inverse.fieldName}: mappedBy="${inverse.mappedBy}" does not match owning field "${relation.fieldName}" in ${relation.ownerEntityName}',
              );
            }
          }
        }
      } else {
        // Inverse side must have mappedBy
        if (relation.mappedBy == null || relation.mappedBy!.isEmpty) {
          errors.add(
            '${relation.ownerEntityName}.${relation.fieldName}: Inverse side must define mappedBy',
          );
        } else {
          // Check that mappedBy references a valid field in target entity
          final targetElement = entityElements[relation.targetEntityName];
          if (targetElement != null) {
            final mappedField = targetElement.fields
                .where((f) => f.name == relation.mappedBy)
                .firstOrNull;
            if (mappedField == null) {
              errors.add(
                '${relation.ownerEntityName}.${relation.fieldName}: mappedBy="${relation.mappedBy}" field not found in ${relation.targetEntityName}',
              );
            }
          }
        }
      }
    }

    return errors;
  }

  /// Deduplicate junction tables - keep only owning side definitions
  /// Also handles the case where both sides have mappedBy (no explicit owning side)
  List<_JunctionTableInfo> _deduplicateJunctionTables(
    List<_ManyToManyInfo> relations,
    Map<String, String> entityToTableName,
  ) {
    final tables = <String, _JunctionTableInfo>{};

    // First, add all explicit owning side relations
    for (final relation in relations.where((r) => r.isOwningSide)) {
      if (!tables.containsKey(relation.joinTableName)) {
        // Look up target table name from the map
        final targetTableName =
            entityToTableName[relation.targetEntityName] ??
            _toSnakeCase(relation.targetEntityName);
        tables[relation.joinTableName] = _JunctionTableInfo(
          tableName: relation.joinTableName,
          ownerTableName: relation.ownerTableName,
          targetTableName: targetTableName,
          joinColumnName: relation.joinColumnName,
          joinColumnRef: relation.joinColumnRef,
          inverseColumnName: relation.inverseColumnName,
          inverseColumnRef: relation.inverseColumnRef,
          createIndex: relation.createIndex,
        );
      }
    }

    // Handle case where both sides have mappedBy (no explicit owning side)
    // Group inverse relations by their entity pair
    final inverseRelations = relations.where((r) => !r.isOwningSide).toList();
    final processedPairs = <String>{};

    for (final relation in inverseRelations) {
      // Create a canonical key for this entity pair (sorted alphabetically)
      final entities = [relation.ownerEntityName, relation.targetEntityName]
        ..sort();
      final pairKey = entities.join('_');

      // Skip if we already processed this pair
      if (processedPairs.contains(pairKey)) continue;

      // Check if there's an owning side for this pair
      final hasOwningSide = relations.any(
        (r) =>
            r.isOwningSide &&
            ((r.ownerEntityName == relation.ownerEntityName &&
                    r.targetEntityName == relation.targetEntityName) ||
                (r.ownerEntityName == relation.targetEntityName &&
                    r.targetEntityName == relation.ownerEntityName)),
      );

      if (!hasOwningSide) {
        // No owning side - auto-generate junction table
        // Use alphabetically first entity's TABLE NAME for consistency
        final ownerTable =
            entityToTableName[entities[0]] ?? _toSnakeCase(entities[0]);
        final targetTable =
            entityToTableName[entities[1]] ?? _toSnakeCase(entities[1]);
        final joinTableName = '${ownerTable}_$targetTable';

        if (!tables.containsKey(joinTableName)) {
          tables[joinTableName] = _JunctionTableInfo(
            tableName: joinTableName,
            ownerTableName: ownerTable,
            targetTableName: targetTable,
            joinColumnName: '${ownerTable}_id',
            joinColumnRef: 'id',
            inverseColumnName: '${targetTable}_id',
            inverseColumnRef: 'id',
            createIndex: true,
          );
        }
        processedPairs.add(pairKey);
      }
    }

    return tables.values.toList();
  }

  /// Extract DbConfig from annotation
  _DbConfigInfo? _extractDbConfig(ConstantReader annotation) {
    final configReader = annotation.peek('config');
    if (configReader == null || configReader.isNull) return null;

    final configObj = configReader.objectValue;
    final host = configObj.getField('host')?.toStringValue() ?? 'localhost';
    final port = configObj.getField('port')?.toIntValue() ?? 5432;
    final database = configObj.getField('database')?.toStringValue() ?? '';
    final username = configObj.getField('username')?.toStringValue();
    final password = configObj.getField('password')?.toStringValue();
    final ssl = configObj.getField('ssl')?.toBoolValue() ?? false;

    // Get dbType from config
    String dbType = 'postgresql';
    final dbTypeField = configObj.getField('dbType');
    if (dbTypeField != null) {
      final index = dbTypeField.getField('index')?.toIntValue();
      if (index == 0)
        dbType = 'postgresql';
      else if (index == 1)
        dbType = 'mysql';
      else if (index == 2)
        dbType = 'sqlite';
    }

    return _DbConfigInfo(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
      dbType: dbType,
      ssl: ssl,
    );
  }

  /// Extract column information from entity class
  List<_ColumnInfo> _extractColumnsFromEntity(ClassElement element) {
    final columns = <_ColumnInfo>[];

    for (final field in element.fields) {
      if (field.isStatic) continue;

      // Check for @Ignore annotation
      bool hasIgnore = false;
      bool isRelationship = false;
      bool isPrimaryKey = false;
      String columnName = _toSnakeCase(field.name!);

      for (final meta in field.metadata.annotations) {
        final annotationName = meta.element?.enclosingElement?.name;
        if (annotationName == 'Ignore') {
          hasIgnore = true;
          break;
        }
        if (annotationName == 'OneToMany' ||
            annotationName == 'ManyToOne' ||
            annotationName == 'ManyToMany') {
          isRelationship = true;
          break;
        }
        if (annotationName == 'Id') {
          isPrimaryKey = true;
        }
        if (annotationName == 'Column') {
          final source = meta.toSource();
          final nameMatch = RegExp(
            'name:\\s*[\'"]([\\w_]+)[\'"]',
          ).firstMatch(source);
          if (nameMatch != null) {
            columnName = nameMatch.group(1)!;
          }
        }
      }

      if (hasIgnore || isRelationship) continue;

      final sqlType = _getDartToSqlType(field.type);
      final isNullable = field.type.nullabilitySuffix.toString().contains(
        'question',
      );

      columns.add(
        _ColumnInfo(
          name: columnName,
          dartType: field.type.getDisplayString(withNullability: true),
          sqlType: sqlType,
          isNullable: isNullable,
          isPrimaryKey: isPrimaryKey,
        ),
      );
    }

    return columns;
  }

  String _getDartToSqlType(DartType type) {
    final name = type.getDisplayString(withNullability: false);
    const typeMap = {
      'String': 'TEXT',
      'int': 'INTEGER',
      'double': 'REAL',
      'bool': 'BOOLEAN',
      'DateTime': 'TIMESTAMP',
    };
    return typeMap[name] ?? 'TEXT';
  }

  String _toSnakeCase(String text) {
    return text
        .replaceAllMapped(
          RegExp('[A-Z]'),
          (m) => '_${m.group(0)!.toLowerCase()}',
        )
        .replaceFirst(RegExp('^_'), '');
  }

  /// Generate a hash of the schema for change detection
  String _generateSchemaHash(
    List<_EntityInfo> entities,
    List<_JunctionTableInfo> junctionTables,
  ) {
    final entitySchemaString = entities
        .map((e) {
          final columnsStr = e.columns
              .map(
                (c) =>
                    '${c.name}:${c.sqlType}:${c.isNullable}:${c.isPrimaryKey}',
              )
              .join(',');
          return '${e.tableName}[$columnsStr]';
        })
        .join('|');

    final junctionSchemaString = junctionTables
        .map(
          (j) => '${j.tableName}[${j.joinColumnName},${j.inverseColumnName}]',
        )
        .join('|');

    final schemaString = '$entitySchemaString||$junctionSchemaString';
    final bytes = utf8.encode(schemaString);
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  String _generateDbCode({
    required String className,
    required List<_EntityInfo> entities,
    required List<_JunctionTableInfo> junctionTables,
    required int migrationVersion,
    _DbConfigInfo? configInfo,
    String? dbName,
    required String schemaHash,
  }) {
    final buffer = StringBuffer();

    // Header comment only - PartBuilder handles 'part of' directive
    buffer.writeln('// Generated database class for $className');
    buffer.writeln('// Migration version: $migrationVersion');
    buffer.writeln('// Schema hash: $schemaHash');
    buffer.writeln();

    // Generate default config if provided in annotation
    if (configInfo != null) {
      buffer.writeln(_generateDefaultConfig(className, configInfo));
    }

    // Schema generation is now handled by DbSchemaGenerator (db.schema.g.dart)
    // which generates databaseSchemas and databaseJunctionSchemas getters

    // Generate singleton repository holders
    buffer.writeln(_generateRepositoryHolders(className, entities));

    // Generate repository extension for database class
    buffer.writeln(_generateRepositoryExtension(className, entities));

    // Generate database lifecycle extension (init, migration, schema)
    buffer.writeln(
      _generateDbLifecycleExtension(
        className,
        entities,
        junctionTables,
        migrationVersion,
        schemaHash,
        configInfo,
      ),
    );

    return buffer.toString();
  }

  /// Generate default DatabaseConfig from annotation
  String _generateDefaultConfig(String className, _DbConfigInfo config) {
    final configMethod = config.dbType == 'sqlite'
        ? 'DatabaseConfig.sqlite'
        : config.dbType == 'mysql'
        ? 'DatabaseConfig.mysql'
        : 'DatabaseConfig.postgresql';

    if (config.dbType == 'sqlite') {
      return '''
/// Default database configuration from @Db annotation
DatabaseConfig _${_toCamelCase(className)}DefaultConfig() => $configMethod(
  path: '${config.database}',
);
''';
    }

    return '''
/// Default database configuration from @Db annotation
DatabaseConfig _${_toCamelCase(className)}DefaultConfig() => $configMethod(
  host: '${config.host}',
  port: ${config.port},
  database: '${config.database}',
  ${config.username != null ? "username: '${config.username}'," : ''}
  ${config.password != null ? "password: '${config.password}'," : ''}
);
''';
  }

  String _generateRepositoryHolders(
    String dbClassName,
    List<_EntityInfo> entities,
  ) {
    final holders = entities
        .map((e) {
          final repoVarName = '_${_toCamelCase(e.repositoryName)}';
          return '${e.repositoryName}? $repoVarName;';
        })
        .join('\n');

    return '''// Singleton repository instances for $dbClassName
$holders
''';
  }

  String _generateRepositoryExtension(
    String dbClassName,
    List<_EntityInfo> entities,
  ) {
    final repoGetters = entities
        .map((e) {
          final privateVarName = '_${_toCamelCase(e.repositoryName)}';
          final publicVarName = _toCamelCase(e.repositoryName);
          return '''  /// Access ${e.className} repository (singleton, initialized on first access after connection)
  ${e.repositoryName} get $publicVarName {
    if ($privateVarName == null) {
      $privateVarName = ${e.repositoryName}();
      if (connection != null) {
        $privateVarName!.setConnection(connection!);
      }
    }
    return $privateVarName!;
  }''';
        })
        .join('\n\n');

    return '''
// Extension to access repositories from $dbClassName
extension ${dbClassName}Repositories on $dbClassName {
$repoGetters
}
''';
  }

  String _generateDbLifecycleExtension(
    String dbClassName,
    List<_EntityInfo> entities,
    List<_JunctionTableInfo> junctionTables,
    int migrationVersion,
    String schemaHash,
    _DbConfigInfo? configInfo,
  ) {
    final hasConfig = configInfo != null;
    final defaultConfigFunc = '_${_toCamelCase(dbClassName)}DefaultConfig';

    return '''
// Database lifecycle extension for $dbClassName
// Note: databaseSchemas and databaseJunctionSchemas getters are in ${dbClassName}Schemas extension (db.schema.g.dart)
extension ${dbClassName}Lifecycle on $dbClassName {
  /// Current migration version for this database
  static const int currentMigrationVersion = $migrationVersion;
  
  /// Schema hash for detecting changes
  static const String schemaHash = '$schemaHash';

  /// Setup database: connect (using config from annotation or parameter), run migrations, validate schema
  /// 
  /// [config] - Optional DatabaseConfig, uses annotation config if not provided
  /// [migrations] - List of migrations to run (sorted by version)
  /// [validateSchema] - If true, validates schema matches database
  /// [autoCreateSchema] - If true, creates all tables before running migrations (default: true)
  /// Throws [StateError] if schema changed but migration version not bumped
  Future<void> setup({
    DatabaseConfig? config,
    List<DatabaseMigration> migrations = const [],
    bool validateSchema = true,
    bool autoCreateSchema = true,
  }) async {
    // Use provided config or default from annotation
    final effectiveConfig = config ${hasConfig ? '?? $defaultConfigFunc()' : ''};
    ${hasConfig ? '' : 'if (effectiveConfig == null) { throw StateError("No DatabaseConfig provided and no default config in @Db annotation"); }'}
    
    // Initialize connection if not already connected
    await init(effectiveConfig);
    
    // Create schema tables (uses IF NOT EXISTS, safe to call multiple times)
    if (autoCreateSchema) {
      await createSchema();
    }
    
    // Run migrations and validate schema
    await initializeDatabase(
      migrations: migrations,
      validateSchema: validateSchema,
    );
  }

  /// Initialize database connection
  Future<void> init(DatabaseConfig${hasConfig ? '?' : ''} config) async {
    if (_connection != null) return;
    ${hasConfig ? 'final effectiveConfig = config ?? $defaultConfigFunc();' : 'final effectiveConfig = config;'}
    _connection = await DatabaseFactory.createConnection(effectiveConfig);
  }

  /// Initialize database: run migrations if needed, validate schema
  /// 
  /// [migrations] - List of migrations to run (sorted by version)
  /// [validateSchema] - If true, validates schema matches database
  /// Throws [StateError] if schema changed but migration version not bumped
  Future<void> initializeDatabase({
    List<DatabaseMigration> migrations = const [],
    bool validateSchema = true,
  }) async {
    // Ensure connection is established
    if (connection == null) {
      throw StateError('Database connection not established. Call init() or setup() first.');
    }

    // Run pending migrations
    if (migrations.isNotEmpty) {
      await _runMigrations(migrations);
    }

    // Validate schema if enabled
    if (validateSchema) {
      final differences = await _checkSchema();
      if (differences.isNotEmpty) {
        // Check if version was bumped
        final storedHash = await _getStoredSchemaHash();
        if (storedHash != null && storedHash != schemaHash) {
          throw StateError(
            'Schema has changed but migration version was not bumped!\\n'
            'Differences found:\\n\${differences.join('\\n')}\\n'
            'Please increment migrationVersion in @Db annotation and create a migration.',
          );
        }
        // Store new hash after successful migration
        await _storeSchemaHash(schemaHash);
      }
    }
  }

  /// Run pending migrations
  Future<void> _runMigrations(List<DatabaseMigration> migrations) async {
    final runner = MigrationRunner(connection!, migrations);
    await runner.runMigrations();
  }

  /// Create all tables from schema definitions (uses IF NOT EXISTS)
  /// Call this after connection is established to ensure all tables exist
  /// Tables that already exist will be skipped
  Future<void> createSchema() async {
    if (connection == null) {
      throw StateError('Database connection not established. Call init() or setup() first.');
    }
    
    final schemaManager = SchemaManager(connection!);
    
    // Create entity tables
    for (final schema in databaseSchemas) {
      await schemaManager.createTable(schema);
    }
    
    // Create junction tables for ManyToMany relationships
    for (final schema in databaseJunctionSchemas) {
      await schemaManager.createTable(schema);
    }
  }

  /// Drop all tables (use with caution!)
  /// Drops tables in reverse order to handle foreign key constraints
  Future<void> dropSchema() async {
    if (connection == null) {
      throw StateError('Database connection not established. Call init() or setup() first.');
    }
    
    final schemaManager = SchemaManager(connection!);
    
    // Drop junction tables first (they reference entity tables)
    for (final schema in databaseJunctionSchemas.reversed) {
      await schemaManager.dropTable(schema);
    }
    
    // Drop entity tables
    for (final schema in databaseSchemas.reversed) {
      await schemaManager.dropTable(schema);
    }
  }

  /// Get SQL statements to create all tables
  List<String> getCreateSchemaSql() {
    final sql = <String>[];
    final dbType = connection?.databaseType ?? DatabaseType.postgresql;
    
    for (final schema in databaseSchemas) {
      sql.addAll(schema.toAllSql(dbType));
    }
    
    for (final schema in databaseJunctionSchemas) {
      sql.addAll(schema.toAllSql(dbType));
    }
    
    return sql;
  }

  /// Check schema differences between code and database
  Future<List<String>> _checkSchema() async {
    final differences = <String>[];
    
    for (final schema in databaseSchemas) {
      final tableName = schema.tableName;
      
      // Check if table exists
      final tableExists = await _tableExists(tableName);
      if (!tableExists) {
        differences.add('Table "\$tableName" does not exist');
        continue;
      }
      
      // Check columns
      final dbColumns = await _getTableColumns(tableName);
      for (final column in schema.columns) {
        if (column is ColumnSchema) {
          if (!dbColumns.contains(column.name)) {
            differences.add('Column "\${column.name}" missing in table "\$tableName"');
          }
        }
      }
    }
    
    return differences;
  }

  /// Retrieve schema from database for a table
  Future<DatabaseSchema?> getSchemaFromDatabase(String tableName) async {
    if (connection == null) return null;
    
    final tableExists = await _tableExists(tableName);
    if (!tableExists) return null;
    
    final sql = "SELECT column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_name = @table ORDER BY ordinal_position";
    final result = await connection!.query(sql, parameters: {'table': tableName});
    
    final columns = result.map((row) => ColumnSchema(
      name: row['column_name'] as String,
      type: row['data_type'] as String,
      nullable: row['is_nullable'] == 'YES',
      primaryKey: false, // Would need additional query to determine
    )).toList();
    
    return DatabaseSchema(tableName: tableName, columns: columns);
  }

  /// Retrieve all schemas from database
  Future<List<DatabaseSchema>> getAllSchemasFromDatabase() async {
    final schemas = <DatabaseSchema>[];
    for (final schema in databaseSchemas) {
      final dbSchema = await getSchemaFromDatabase(schema.tableName);
      if (dbSchema != null) {
        schemas.add(dbSchema);
      }
    }
    return schemas;
  }

  /// Check if table exists in database
  Future<bool> _tableExists(String tableName) async {
    final sql = "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = @table)";
    final result = await connection!.query(sql, parameters: {'table': tableName});
    return result.isNotEmpty && result.first['exists'] == true;
  }

  /// Get column names for a table
  Future<List<String>> _getTableColumns(String tableName) async {
    final sql = "SELECT column_name FROM information_schema.columns WHERE table_name = @table";
    final result = await connection!.query(sql, parameters: {'table': tableName});
    return result.map((r) => r['column_name'] as String).toList();
  }

  /// Get stored schema hash from database
  Future<String?> _getStoredSchemaHash() async {
    try {
      await connection!.execute(
        "CREATE TABLE IF NOT EXISTS __schema_info__ (key VARCHAR(50) PRIMARY KEY, value TEXT NOT NULL)"
      );
      final result = await connection!.query(
        "SELECT value FROM __schema_info__ WHERE key = 'schema_hash'",
      );
      if (result.isEmpty) return null;
      return result.first['value'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Store schema hash in database
  Future<void> _storeSchemaHash(String hash) async {
    await connection!.execute(
      "INSERT INTO __schema_info__ (key, value) VALUES ('schema_hash', @hash) ON CONFLICT (key) DO UPDATE SET value = @hash",
      parameters: {'hash': hash},
    );
  }

  /// Get current applied migration version from database
  Future<int> getAppliedMigrationVersion() async {
    if (connection == null) return 0;
    
    try {
      final sql = 'SELECT MAX(version) as version FROM __migrations__';
      final result = await connection!.query(sql);
      if (result.isEmpty || result.first['version'] == null) return 0;
      return result.first['version'] as int;
    } catch (_) {
      return 0; // Table doesn't exist yet
    }
  }

  /// Check if migrations are pending
  Future<bool> hasPendingMigrations(List<DatabaseMigration> migrations) async {
    final appliedVersion = await getAppliedMigrationVersion();
    return migrations.any((m) => m.version > appliedVersion);
  }

  /// Run a single ad-hoc SQL statement (not tracked in migrations table)
  /// Use this for one-off operations that don't need version tracking
  Future<void> runSql(String sql, {Map<String, dynamic>? parameters}) async {
    if (connection == null) {
      throw StateError('Database connection not established. Call init() or setup() first.');
    }
    await connection!.execute(sql, parameters: parameters);
  }

  /// Run multiple ad-hoc SQL statements (not tracked in migrations table)
  Future<void> runSqlStatements(List<String> statements) async {
    if (connection == null) {
      throw StateError('Database connection not established. Call init() or setup() first.');
    }
    for (final sql in statements) {
      await connection!.execute(sql);
    }
  }

  /// Run a callback with access to connection and schema manager (not tracked)
  /// 
  /// Example:
  /// ```dart
  /// await db.runManual((connection, schemaManager) async {
  ///   await connection.execute('ALTER TABLE users ADD COLUMN age INTEGER;');
  ///   await schemaManager.createIndex(
  ///     name: 'idx_users_age',
  ///     table: 'users',
  ///     columns: ['age'],
  ///   );
  /// });
  /// ```
  Future<void> runManual(MigrationCallback callback) async {
    if (connection == null) {
      throw StateError('Database connection not established. Call init() or setup() first.');
    }
    final schemaManager = SchemaManager(connection!);
    await callback(connection!, schemaManager);
  }

  /// Rollback the last applied migration
  Future<void> rollbackLastMigration(List<DatabaseMigration> migrations) async {
    if (connection == null) {
      throw StateError('Database connection not established. Call init() or setup() first.');
    }
    final runner = MigrationRunner(connection!, migrations);
    await runner.rollbackLast();
  }

  /// Close database connection
  Future<void> close() async {
    await _connection?.close();
    _connection = null;
  }
}
''';
  }

  String _toCamelCase(String text) {
    if (text.isEmpty) return text;
    return text[0].toLowerCase() + text.substring(1);
  }
}

class _EntityInfo {
  final String className;
  final String repositoryName;
  final String tableName;
  final List<_ColumnInfo> columns;

  _EntityInfo({
    required this.className,
    required this.repositoryName,
    required this.tableName,
    required this.columns,
  });
}

class _ColumnInfo {
  final String name;
  final String dartType;
  final String sqlType;
  final bool isNullable;
  final bool isPrimaryKey;

  _ColumnInfo({
    required this.name,
    required this.dartType,
    required this.sqlType,
    required this.isNullable,
    required this.isPrimaryKey,
  });
}

class _DbConfigInfo {
  final String host;
  final int port;
  final String database;
  final String? username;
  final String? password;
  final String dbType;
  final bool ssl;

  _DbConfigInfo({
    required this.host,
    required this.port,
    required this.database,
    this.username,
    this.password,
    required this.dbType,
    required this.ssl,
  });
}

class _ManyToManyInfo {
  final String ownerEntityName;
  final String ownerTableName;
  final String targetEntityName;
  final String fieldName;
  final String joinTableName;
  final String joinColumnName;
  final String joinColumnRef;
  final String inverseColumnName;
  final String inverseColumnRef;
  final bool isOwningSide;
  final String? mappedBy;
  final bool createIndex;

  _ManyToManyInfo({
    required this.ownerEntityName,
    required this.ownerTableName,
    required this.targetEntityName,
    required this.fieldName,
    required this.joinTableName,
    required this.joinColumnName,
    required this.joinColumnRef,
    required this.inverseColumnName,
    required this.inverseColumnRef,
    required this.isOwningSide,
    this.mappedBy,
    required this.createIndex,
  });
}

class _JunctionTableInfo {
  final String tableName;
  final String ownerTableName;
  final String targetTableName;
  final String joinColumnName;
  final String joinColumnRef;
  final String inverseColumnName;
  final String inverseColumnRef;
  final bool createIndex;

  _JunctionTableInfo({
    required this.tableName,
    required this.ownerTableName,
    required this.targetTableName,
    required this.joinColumnName,
    required this.joinColumnRef,
    required this.inverseColumnName,
    required this.inverseColumnRef,
    required this.createIndex,
  });
}

Builder dbGeneratorBuilder(BuilderOptions options) {
  return PartBuilder(
    [DbGenerator()],
    '.db.g.dart',
  );
}
