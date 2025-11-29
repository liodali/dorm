import 'dart:convert';
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

    // Extract DbConfig from annotation
    final configInfo = _extractDbConfig(annotation);

    // Extract entity types and their schema info from annotation
    final entitiesReader = annotation.peek('entities');
    final entities = <_EntityInfo>[];

    if (entitiesReader != null && !entitiesReader.isNull) {
      final entityList = entitiesReader.listValue;
      for (final entityValue in entityList) {
        final typeValue = entityValue.toTypeValue();
        if (typeValue != null) {
          final entityElement = typeValue.element;
          if (entityElement is ClassElement && entityElement.name != null) {
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

            // Extract fields/columns from entity
            final columns = _extractColumnsFromEntity(entityElement);

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

    // Generate schema hash to detect changes
    final schemaHash = _generateSchemaHash(entities);

    return _generateDbCode(
      className: className!,
      entities: entities,
      migrationVersion: migrationVersion,
      configInfo: configInfo,
      dbName: dbName,
      schemaHash: schemaHash,
    );
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
  String _generateSchemaHash(List<_EntityInfo> entities) {
    final schemaString = entities
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

    final bytes = utf8.encode(schemaString);
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  String _generateDbCode({
    required String className,
    required List<_EntityInfo> entities,
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

    // Generate database schema (linked to database, not entity)
    buffer.writeln(_generateDatabaseSchema(className, entities));

    // Generate singleton repository holders
    buffer.writeln(_generateRepositoryHolders(className, entities));

    // Generate repository extension for database class
    buffer.writeln(_generateRepositoryExtension(className, entities));

    // Generate database lifecycle extension (init, migration, schema)
    buffer.writeln(
      _generateDbLifecycleExtension(
        className,
        entities,
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

  /// Generate database schema definition
  String _generateDatabaseSchema(
    String dbClassName,
    List<_EntityInfo> entities,
  ) {
    final schemas = entities
        .map((e) {
          final columns = e.columns
              .map((c) {
                return '''    ColumnSchema(
      name: '${c.name}',
      type: '${c.sqlType}',
      nullable: ${c.isNullable},
      primaryKey: ${c.isPrimaryKey},
    )''';
              })
              .join(',\n');

          return '''
// Schema for ${e.className} table
const ${_toCamelCase(e.className)}Schema = DatabaseSchema(
  tableName: '${e.tableName}',
  columns: [
$columns
  ],
);''';
        })
        .join('\n\n');

    return '''// Database schemas for $dbClassName
$schemas

// All schemas for this database
const ${_toCamelCase(dbClassName)}Schemas = [${entities.map((e) => '${_toCamelCase(e.className)}Schema').join(', ')}];
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
    int migrationVersion,
    String schemaHash,
    _DbConfigInfo? configInfo,
  ) {
    final schemaListVar = '${_toCamelCase(dbClassName)}Schemas';
    final hasConfig = configInfo != null;
    final defaultConfigFunc = '_${_toCamelCase(dbClassName)}DefaultConfig';

    return '''
// Database lifecycle extension for $dbClassName
extension ${dbClassName}Lifecycle on $dbClassName {
  /// Current migration version for this database
  static const int currentMigrationVersion = $migrationVersion;
  
  /// Schema hash for detecting changes
  static const String schemaHash = '$schemaHash';

  /// Get all schemas for this database
  List<DatabaseSchema> get schemas => $schemaListVar;

  /// Setup database: connect (using config from annotation or parameter), run migrations, validate schema
  /// 
  /// [config] - Optional DatabaseConfig, uses annotation config if not provided
  /// [migrations] - List of migrations to run (sorted by version)
  /// [validateSchema] - If true, validates schema matches database
  /// Throws [StateError] if schema changed but migration version not bumped
  Future<void> setup({
    DatabaseConfig? config,
    List<DatabaseMigration> migrations = const [],
    bool validateSchema = true,
  }) async {
    // Use provided config or default from annotation
    final effectiveConfig = config ${hasConfig ? '?? $defaultConfigFunc()' : ''};
    ${hasConfig ? '' : 'if (effectiveConfig == null) { throw StateError("No DatabaseConfig provided and no default config in @Db annotation"); }'}
    
    // Initialize connection if not already connected
    await init(effectiveConfig);
    
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

  /// Check schema differences between code and database
  Future<List<String>> _checkSchema() async {
    final differences = <String>[];
    
    for (final schema in $schemaListVar) {
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
    for (final schema in $schemaListVar) {
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

Builder dbGeneratorBuilder(BuilderOptions options) {
  return PartBuilder(
    [DbGenerator()],
    '.db.g.dart',
  );
}
