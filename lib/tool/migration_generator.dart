import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:crypto/crypto.dart';
import 'package:dartorm/src/annotation.dart';
import 'package:dartorm/src/schema.dart' show SQLType;
import 'package:source_gen/source_gen.dart';

/// Generator for database migrations
/// Generates migrations in .migration.g.dart as part of the database file
///
/// Uses stored schema JSON to detect changes:
/// - If no previous schema exists: generates initial migration (version 1)
/// - If schema changed: generates diff migration for the changes
/// - If no changes: generates empty migration file (just extension)
class MigrationGenerator extends GeneratorForAnnotation<Db> {
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
    final sqlDialectValue = annotation.peek('sqlDialect')?.objectValue;
    final dbName =
        annotation.peek('name')?.stringValue ?? className!.toLowerCase();

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

    // Get schema storage path
    final inputPath = buildStep.inputId.path;
    final packageRoot = inputPath.split('lib/').first;
    final schemaFilePath = '$packageRoot.dorm/$dbName.schema.json';

    // Extract entity types and their schema info from annotation
    final entitiesReader = annotation.peek('entities');
    final entities = <_EntityInfo>[];
    final manyToManyRelations = <_ManyToManyInfo>[];
    final entityElements = <String, ClassElement>{};
    final entityToTableName = <String, String>{};

    // Collect OneToMany relationships to add FK columns to target entities
    final oneToManyRelations = <_OneToManyInfo>[];

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

      // Second pass: extract OneToMany relationships first
      for (final entityValue in entityList) {
        final typeValue = entityValue.toTypeValue();
        if (typeValue != null) {
          final entityElement = typeValue.element;
          if (entityElement is ClassElement && entityElement.name != null) {
            final tableName = entityToTableName[entityElement.name!]!;

            // Extract OneToMany relationships
            final o2mRelations = _extractOneToManyRelations(
              entityElement,
              tableName,
              entityToTableName,
            );
            oneToManyRelations.addAll(o2mRelations);
          }
        }
      }

      // Third pass: extract entity info and relationships
      for (final entityValue in entityList) {
        final typeValue = entityValue.toTypeValue();
        if (typeValue != null) {
          final entityElement = typeValue.element;
          if (entityElement is ClassElement && entityElement.name != null) {
            final tableName = entityToTableName[entityElement.name!]!;

            // Extract fields/columns from entity
            final columns = _extractColumnsFromEntity(entityElement);

            // Extract ManyToOne relationships and add FK columns if not already present
            final manyToOneRelations = _extractManyToOneRelations(
              entityElement,
              tableName,
              entityToTableName,
            );

            // Add FK columns from ManyToOne relationships if not already in columns
            for (final m2oRel in manyToOneRelations) {
              final fkColumnExists = columns.any(
                (c) => c.name == m2oRel.foreignKeyColumn,
              );
              if (!fkColumnExists) {
                columns.add(
                  _ColumnInfo(
                    name: m2oRel.foreignKeyColumn,
                    dartType: 'int?',
                    sqlType: 'INTEGER',
                    isNullable: m2oRel.nullable,
                    isPrimaryKey: false,
                  ),
                );
              }
            }

            // Add FK columns from OneToMany relationships (where this entity is the target)
            for (final o2mRel in oneToManyRelations) {
              if (o2mRel.targetTableName == tableName) {
                final fkColumnExists = columns.any(
                  (c) => c.name == o2mRel.foreignKeyColumn,
                );
                if (!fkColumnExists) {
                  columns.add(
                    _ColumnInfo(
                      name: o2mRel.foreignKeyColumn,
                      dartType: 'int?',
                      sqlType: 'INTEGER',
                      isNullable: true,
                      isPrimaryKey: false,
                    ),
                  );
                }
                // Also add to manyToOneRelations for FK constraint generation
                manyToOneRelations.add(
                  _ManyToOneInfo(
                    ownerEntityName: o2mRel.targetEntityName,
                    ownerTableName: o2mRel.targetTableName,
                    targetEntityName: o2mRel.ownerEntityName,
                    targetTableName: o2mRel.ownerTableName,
                    fieldName: '',
                    foreignKeyColumn: o2mRel.foreignKeyColumn,
                    referencedColumn: o2mRel.referencedColumn,
                    nullable: true,
                    onDelete: o2mRel.onDelete,
                    onUpdate: o2mRel.onUpdate,
                  ),
                );
              }
            }

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
                manyToOneRelations: manyToOneRelations,
              ),
            );
          }
        }
      }
    }

    // Deduplicate junction tables (keep only owning side)
    final junctionTables = _deduplicateJunctionTables(
      manyToManyRelations,
      entityToTableName,
    );

    // Generate current schema as JSON
    final currentSchema = _schemaToJson(entities, junctionTables);
    final schemaHash = _generateSchemaHash(entities, junctionTables);

    // Migration history file path
    final migrationsFilePath = '$packageRoot.dorm/$dbName.migrations.json';

    // Load previous schema and migration history
    final previousSchema = await _loadPreviousSchema(schemaFilePath);
    final migrationHistory = await _loadMigrationHistory(migrationsFilePath);

    // Compare schemas to detect changes
    final schemaChanges = _compareSchemas(previousSchema, currentSchema);

    // Determine if we need a new migration
    final hasChanges = schemaChanges.isNotEmpty;
    final isInitial = previousSchema == null;

    // Update migration history if there are changes
    if (hasChanges && !isInitial) {
      await _addMigrationToHistory(
        migrationsFilePath,
        migrationHistory,
        migrationVersion,
        schemaChanges,
        schemaHash,
      );
    } else if (isInitial) {
      // Initialize migration history with version 1
      await _initializeMigrationHistory(
        migrationsFilePath,
        schemaHash,
      );
    }

    // Save current schema for next comparison
    await _saveSchema(schemaFilePath, currentSchema);

    // Reload migration history after updates
    final updatedHistory = await _loadMigrationHistory(migrationsFilePath);

    return _generateMigrationCode(
      className: className!,
      entities: entities,
      junctionTables: junctionTables,
      migrationVersion: migrationVersion,
      sqlDialect: sqlDialect,
      schemaHash: schemaHash,
      previousSchema: previousSchema,
      schemaChanges: schemaChanges,
      migrationHistory: updatedHistory,
    );
  }

  /// Convert schema to JSON for storage
  Map<String, dynamic> _schemaToJson(
    List<_EntityInfo> entities,
    List<_JunctionTableInfo> junctionTables,
  ) {
    return {
      'version': 1,
      'generatedAt': DateTime.now().toIso8601String(),
      'tables': entities
          .map(
            (e) => {
              'name': e.tableName,
              'className': e.className,
              'columns': e.columns
                  .map(
                    (c) => {
                      'name': c.name,
                      'type': c.sqlType,
                      'nullable': c.isNullable,
                      'primaryKey': c.isPrimaryKey,
                    },
                  )
                  .toList(),
              'foreignKeys': e.manyToOneRelations
                  .map(
                    (fk) => {
                      'column': fk.foreignKeyColumn,
                      'referencedTable': fk.targetTableName,
                      'referencedColumn': fk.referencedColumn,
                      'onDelete': fk.onDelete,
                      'onUpdate': fk.onUpdate,
                    },
                  )
                  .toList(),
            },
          )
          .toList(),
      'junctionTables': junctionTables
          .map(
            (j) => {
              'name': j.tableName,
              'ownerTable': j.ownerTableName,
              'targetTable': j.targetTableName,
              'joinColumn': j.joinColumnName,
              'inverseColumn': j.inverseColumnName,
            },
          )
          .toList(),
    };
  }

  /// Load previous schema from JSON file
  Future<Map<String, dynamic>?> _loadPreviousSchema(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return null;
    }
    try {
      final content = await file.readAsString();
      return json.decode(content) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Save current schema to JSON file
  Future<void> _saveSchema(String filePath, Map<String, dynamic> schema) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(schema),
    );
  }

  /// Load migration history from JSON file
  Future<Map<String, dynamic>?> _loadMigrationHistory(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return null;
    }
    try {
      final content = await file.readAsString();
      return json.decode(content) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Initialize migration history with initial migration
  Future<void> _initializeMigrationHistory(
    String filePath,
    String schemaHash,
  ) async {
    final history = {
      'version': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'migrations': [
        {
          'version': 1,
          'description': 'Initial schema creation',
          'schemaHash': schemaHash,
          'createdAt': DateTime.now().toIso8601String(),
          'changes': ['initial'],
        },
      ],
    };
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(history),
    );
  }

  /// Add a new migration to history
  Future<void> _addMigrationToHistory(
    String filePath,
    Map<String, dynamic>? existingHistory,
    int version,
    List<_SchemaChange> changes,
    String schemaHash,
  ) async {
    final migrations = existingHistory?['migrations'] as List? ?? [];

    // Check if this version already exists
    final existingVersions = migrations.map((m) => m['version'] as int).toSet();
    if (existingVersions.contains(version)) {
      // Version already exists, don't add duplicate
      return;
    }

    // Add new migration
    migrations.add({
      'version': version,
      'description': 'Schema changes - version $version',
      'schemaHash': schemaHash,
      'createdAt': DateTime.now().toIso8601String(),
      'changes': changes
          .map(
            (c) => {
              'type': c.type.name,
              'table': c.tableName,
              'column': c.columnName,
              'details': c.details,
            },
          )
          .toList(),
    });

    final history = {
      'version': 1,
      'createdAt':
          existingHistory?['createdAt'] ?? DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
      'migrations': migrations,
    };

    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(history),
    );
  }

  /// Compare schemas and return list of changes
  List<_SchemaChange> _compareSchemas(
    Map<String, dynamic>? oldSchema,
    Map<String, dynamic> newSchema,
  ) {
    final changes = <_SchemaChange>[];

    if (oldSchema == null) {
      // No previous schema - this is initial migration
      return changes;
    }

    final oldTables = Map<String, dynamic>.fromEntries(
      (oldSchema['tables'] as List? ?? []).map(
        (t) => MapEntry(t['name'] as String, t),
      ),
    );
    final newTables = Map<String, dynamic>.fromEntries(
      (newSchema['tables'] as List? ?? []).map(
        (t) => MapEntry(t['name'] as String, t),
      ),
    );

    // Detect added tables
    for (final entry in newTables.entries) {
      if (!oldTables.containsKey(entry.key)) {
        changes.add(
          _SchemaChange(
            type: _ChangeType.addTable,
            tableName: entry.key,
            details: entry.value,
          ),
        );
      }
    }

    // Detect removed tables
    for (final entry in oldTables.entries) {
      if (!newTables.containsKey(entry.key)) {
        changes.add(
          _SchemaChange(
            type: _ChangeType.dropTable,
            tableName: entry.key,
            details: entry.value,
          ),
        );
      }
    }

    // Detect column changes in existing tables
    for (final entry in newTables.entries) {
      if (oldTables.containsKey(entry.key)) {
        final oldTable = oldTables[entry.key]!;
        final newTable = entry.value;

        final columnChanges = _compareTableColumns(
          entry.key,
          oldTable['columns'] as List? ?? [],
          newTable['columns'] as List? ?? [],
        );
        changes.addAll(columnChanges);
      }
    }

    // Compare junction tables
    final oldJunctions = Map<String, dynamic>.fromEntries(
      (oldSchema['junctionTables'] as List? ?? []).map(
        (t) => MapEntry(t['name'] as String, t),
      ),
    );
    final newJunctions = Map<String, dynamic>.fromEntries(
      (newSchema['junctionTables'] as List? ?? []).map(
        (t) => MapEntry(t['name'] as String, t),
      ),
    );

    for (final entry in newJunctions.entries) {
      if (!oldJunctions.containsKey(entry.key)) {
        changes.add(
          _SchemaChange(
            type: _ChangeType.addJunctionTable,
            tableName: entry.key,
            details: entry.value,
          ),
        );
      }
    }

    for (final entry in oldJunctions.entries) {
      if (!newJunctions.containsKey(entry.key)) {
        changes.add(
          _SchemaChange(
            type: _ChangeType.dropJunctionTable,
            tableName: entry.key,
            details: entry.value,
          ),
        );
      }
    }

    return changes;
  }

  /// Compare columns between old and new table
  List<_SchemaChange> _compareTableColumns(
    String tableName,
    List<dynamic> oldColumns,
    List<dynamic> newColumns,
  ) {
    final changes = <_SchemaChange>[];

    final oldColMap = Map<String, dynamic>.fromEntries(
      oldColumns.map((c) => MapEntry(c['name'] as String, c)),
    );
    final newColMap = Map<String, dynamic>.fromEntries(
      newColumns.map((c) => MapEntry(c['name'] as String, c)),
    );

    // Added columns
    for (final entry in newColMap.entries) {
      if (!oldColMap.containsKey(entry.key)) {
        changes.add(
          _SchemaChange(
            type: _ChangeType.addColumn,
            tableName: tableName,
            columnName: entry.key,
            details: entry.value,
          ),
        );
      }
    }

    // Removed columns
    for (final entry in oldColMap.entries) {
      if (!newColMap.containsKey(entry.key)) {
        changes.add(
          _SchemaChange(
            type: _ChangeType.dropColumn,
            tableName: tableName,
            columnName: entry.key,
            details: entry.value,
          ),
        );
      }
    }

    // Modified columns
    for (final entry in newColMap.entries) {
      if (oldColMap.containsKey(entry.key)) {
        final oldCol = oldColMap[entry.key]!;
        final newCol = entry.value;

        if (oldCol['type'] != newCol['type'] ||
            oldCol['nullable'] != newCol['nullable']) {
          changes.add(
            _SchemaChange(
              type: _ChangeType.alterColumn,
              tableName: tableName,
              columnName: entry.key,
              details: {'old': oldCol, 'new': newCol},
            ),
          );
        }
      }
    }

    return changes;
  }

  String _generateMigrationCode({
    required String className,
    required List<_EntityInfo> entities,
    required List<_JunctionTableInfo> junctionTables,
    required int migrationVersion,
    required String sqlDialect,
    required String schemaHash,
    required Map<String, dynamic>? previousSchema,
    required List<_SchemaChange> schemaChanges,
    required Map<String, dynamic>? migrationHistory,
  }) {
    final buffer = StringBuffer();

    // Get all migrations from history
    final storedMigrations = (migrationHistory?['migrations'] as List?) ?? [];
    final migrationVersions =
        storedMigrations.map((m) => m['version'] as int).toList()..sort();

    // Header comment
    buffer.writeln('// Generated migrations for $className');
    buffer.writeln('// Migration version: $migrationVersion');
    buffer.writeln('// Schema hash: $schemaHash');
    buffer.writeln('// SQL Dialect: $sqlDialect');
    buffer.writeln('// Stored migrations: ${migrationVersions.join(', ')}');

    if (previousSchema == null) {
      buffer.writeln(
        '// Status: Initial schema - generating initial migration',
      );
    } else if (schemaChanges.isEmpty) {
      buffer.writeln('// Status: No schema changes detected');
    } else {
      buffer.writeln(
        '// Status: ${schemaChanges.length} schema change(s) detected',
      );
    }
    buffer.writeln();

    // Generate migrations list from history
    buffer.writeln(
      _generateMigrationsGetterFromHistory(className, storedMigrations),
    );

    // Always generate initial migration (version 1)
    buffer.writeln(
      _generateInitialMigration(
        className,
        entities,
        junctionTables,
        sqlDialect,
      ),
    );

    // Generate all stored diff migrations from history
    for (final migration in storedMigrations) {
      final version = migration['version'] as int;
      if (version == 1) continue; // Skip initial migration

      final changes =
          (migration['changes'] as List?)
              ?.map(
                (c) => _SchemaChange(
                  type: _ChangeType.values.firstWhere(
                    (t) => t.name == c['type'],
                    orElse: () => _ChangeType.addColumn,
                  ),
                  tableName: c['table'] as String? ?? '',
                  columnName: c['column'] as String?,
                  details: c['details'],
                ),
              )
              .toList() ??
          [];

      if (changes.isNotEmpty) {
        buffer.writeln(
          _generateDiffMigration(
            className,
            changes,
            version,
            sqlDialect,
          ),
        );
      }
    }

    // Generate migration extension
    buffer.writeln(_generateMigrationExtension(className, migrationVersion));

    return buffer.toString();
  }

  String _generateMigrationsGetterFromHistory(
    String className,
    List<dynamic> migrations,
  ) {
    final versions = migrations.map((m) => m['version'] as int).toList()
      ..sort();

    final migrationInstances = versions
        .map((v) {
          if (v == 1) {
            return '  _${className}InitialMigration(),';
          } else {
            return '  _${className}Migration$v(),';
          }
        })
        .join('\n');

    return '''
/// Generated migrations for $className
/// Migrations are loaded from stored history to preserve across rebuilds
List<DatabaseMigration> get _${_toCamelCase(className)}GeneratedMigrations => [
$migrationInstances
];
''';
  }

  String _generateDiffMigration(
    String className,
    List<_SchemaChange> changes,
    int version,
    String sqlDialect,
  ) {
    final buffer = StringBuffer();

    buffer.writeln('''
/// Schema diff migration - version $version
/// Changes detected:
''');

    for (final change in changes) {
      buffer.writeln(
        '/// - ${change.type.name}: ${change.tableName}${change.columnName != null ? '.${change.columnName}' : ''}',
      );
    }

    buffer.writeln('''
class _${className}Migration$version extends DatabaseMigration {
  @override
  int get version => $version;

  @override
  String get description => 'Schema changes - version $version';

  @override
  Future<void> up() async {
''');

    // Generate up statements
    for (final change in changes) {
      switch (change.type) {
        case _ChangeType.addTable:
          final table = change.details as Map<String, dynamic>;
          buffer.writeln("    // Add table ${change.tableName}");
          buffer.writeln("    await createTable(");
          buffer.writeln("      DatabaseSchema(");
          buffer.writeln("        tableName: '${change.tableName}',");
          buffer.writeln("        columns: [");
          for (final col in (table['columns'] as List? ?? [])) {
            final pkStr = col['primaryKey'] == true ? ', primaryKey: true' : '';
            final nullStr = col['nullable'] == true ? ', nullable: true' : '';
            final sqlTypeEnum = _toSQLTypeEnum(col['type'] as String);
            buffer.writeln(
              "          ColumnSchema(name: '${col['name']}', type: SQLType.${sqlTypeEnum.name}.sqlType$nullStr$pkStr),",
            );
          }
          buffer.writeln("        ],");
          buffer.writeln("      ),");
          buffer.writeln("    );");
          break;

        case _ChangeType.dropTable:
          buffer.writeln("    await dropTable('${change.tableName}');");
          break;

        case _ChangeType.addColumn:
          final col = change.details as Map<String, dynamic>;
          final sqlType = _toSQLTypeEnum(col['type'] as String);
          final nullable = col['nullable'] == true;
          final defaultValue = _getDefaultValueForType(sqlType, nullable);
          buffer.writeln(
            "    await addColumn(table: '${change.tableName}', column: '${change.columnName}', type: SQLType.${sqlType.name}.sqlType, nullable: $nullable, defaultValue: '$defaultValue');",
          );
          break;

        case _ChangeType.dropColumn:
          buffer.writeln(
            "    await dropColumn(table: '${change.tableName}', column: '${change.columnName}');",
          );
          break;

        case _ChangeType.alterColumn:
          final details = change.details as Map<String, dynamic>;
          final newCol = details['new'] as Map<String, dynamic>;
          buffer.writeln(
            "    // Alter column ${change.columnName} in ${change.tableName}",
          );
          buffer.writeln(
            "    await connection.execute(\"ALTER TABLE ${change.tableName} ALTER COLUMN ${change.columnName} TYPE ${newCol['type']}\");",
          );
          break;

        case _ChangeType.addJunctionTable:
          final junction = change.details as Map<String, dynamic>;
          buffer.writeln("    // Add junction table ${change.tableName}");
          buffer.writeln("    await createTable(");
          buffer.writeln("      DatabaseSchema(");
          buffer.writeln("        tableName: '${change.tableName}',");
          buffer.writeln("        columns: [");
          buffer.writeln(
            "          ColumnSchema(name: '${junction['joinColumn']}', type: SQLType.integer.sqlType),",
          );
          buffer.writeln(
            "          ColumnSchema(name: '${junction['inverseColumn']}', type: SQLType.integer.sqlType),",
          );
          buffer.writeln("        ],");
          buffer.writeln(
            "        primaryKeyColumns: ['${junction['joinColumn']}', '${junction['inverseColumn']}'],",
          );
          buffer.writeln("        foreignKeys: [");
          buffer.writeln(
            "          ForeignKey(column: '${junction['joinColumn']}', referencedTable: '${junction['ownerTable']}', referencedColumn: 'id', onDelete: ForeignKeyAction.cascade),",
          );
          buffer.writeln(
            "          ForeignKey(column: '${junction['inverseColumn']}', referencedTable: '${junction['targetTable']}', referencedColumn: 'id', onDelete: ForeignKeyAction.cascade),",
          );
          buffer.writeln("        ],");
          buffer.writeln("      ),");
          buffer.writeln("    );");
          break;

        case _ChangeType.dropJunctionTable:
          buffer.writeln("    await dropTable('${change.tableName}');");
          break;
      }
    }

    buffer.writeln('  }');
    buffer.writeln();

    // Generate down statements (reverse order)
    buffer.writeln('  @override');
    buffer.writeln('  Future<void> down() async {');

    for (final change in changes.reversed) {
      switch (change.type) {
        case _ChangeType.addTable:
          buffer.writeln("    await dropTable('${change.tableName}');");
          break;

        case _ChangeType.dropTable:
          buffer.writeln(
            "    // Cannot restore dropped table ${change.tableName} - manual intervention required",
          );
          break;

        case _ChangeType.addColumn:
          buffer.writeln(
            "    await dropColumn(table: '${change.tableName}', column: '${change.columnName}');",
          );
          break;

        case _ChangeType.dropColumn:
          buffer.writeln(
            "    // Cannot restore dropped column ${change.columnName} - manual intervention required",
          );
          break;

        case _ChangeType.alterColumn:
          final details = change.details as Map<String, dynamic>;
          final oldCol = details['old'] as Map<String, dynamic>;
          buffer.writeln(
            "    await connection.execute(\"ALTER TABLE ${change.tableName} ALTER COLUMN ${change.columnName} TYPE ${oldCol['type']}\");",
          );
          break;

        case _ChangeType.addJunctionTable:
          buffer.writeln("    await dropTable('${change.tableName}');");
          break;

        case _ChangeType.dropJunctionTable:
          buffer.writeln(
            "    // Cannot restore dropped junction table ${change.tableName} - manual intervention required",
          );
          break;
      }
    }

    buffer.writeln('  }');
    buffer.writeln('}');

    return buffer.toString();
  }

  String _generateInitialMigration(
    String className,
    List<_EntityInfo> entities,
    List<_JunctionTableInfo> junctionTables,
    String sqlDialect,
  ) {
    final buffer = StringBuffer();

    buffer.writeln('''
/// Initial schema migration - creates all tables
/// Version: 1
/// This migration creates the initial database schema
class _${className}InitialMigration extends DatabaseMigration {
  @override
  int get version => 1;

  @override
  String get description => 'Initial schema creation';

  @override
  Future<void> up() async {
''');

    // Generate CREATE TABLE statements for entities
    for (final entity in entities) {
      buffer.writeln('    // Create ${entity.tableName} table');
      buffer.writeln('    await createTable(');
      buffer.writeln('      DatabaseSchema(');
      buffer.writeln("        tableName: '${entity.tableName}',");
      buffer.writeln('        columns: [');

      for (final column in entity.columns) {
        final pkStr = column.isPrimaryKey ? ', primaryKey: true' : '';
        final nullableStr = column.isNullable ? ', nullable: true' : '';
        final sqlTypeEnum = _toSQLTypeEnum(column.sqlType);
        buffer.writeln(
          "          ColumnSchema(name: '${column.name}', type: SQLType.${sqlTypeEnum.name}.sqlType$nullableStr$pkStr),",
        );
      }

      buffer.writeln('        ],');

      // Add foreign key constraints
      if (entity.manyToOneRelations.isNotEmpty) {
        buffer.writeln('        foreignKeys: [');
        for (final fk in entity.manyToOneRelations) {
          final onDeleteAction = _relationActionToCode(fk.onDelete);
          final onUpdateAction = _relationActionToCode(fk.onUpdate);
          buffer.writeln(
            "          ForeignKey(column: '${fk.foreignKeyColumn}', referencedTable: '${fk.targetTableName}', referencedColumn: '${fk.referencedColumn}'$onDeleteAction$onUpdateAction),",
          );
        }
        buffer.writeln('        ],');
      }

      buffer.writeln('      ),');
      buffer.writeln('    );');
      buffer.writeln();
    }

    // Generate CREATE TABLE statements for junction tables
    for (final junction in junctionTables) {
      buffer.writeln('    // Create ${junction.tableName} junction table');
      buffer.writeln('    await createTable(');
      buffer.writeln('      DatabaseSchema(');
      buffer.writeln("        tableName: '${junction.tableName}',");
      buffer.writeln('        columns: [');
      buffer.writeln(
        "          ColumnSchema(name: '${junction.joinColumnName}', type: SQLType.integer.sqlType),",
      );
      buffer.writeln(
        "          ColumnSchema(name: '${junction.inverseColumnName}', type: SQLType.integer.sqlType),",
      );
      buffer.writeln('        ],');
      buffer.writeln('        foreignKeys: [');
      buffer.writeln(
        "          ForeignKey(column: '${junction.joinColumnName}', referencedTable: '${junction.ownerTableName}', referencedColumn: '${junction.joinColumnRef}', onDelete: ForeignKeyAction.cascade),",
      );
      buffer.writeln(
        "          ForeignKey(column: '${junction.inverseColumnName}', referencedTable: '${junction.targetTableName}', referencedColumn: '${junction.inverseColumnRef}', onDelete: ForeignKeyAction.cascade),",
      );
      buffer.writeln('        ],');
      buffer.writeln('        primaryKeyColumns: [');
      buffer.writeln("          '${junction.joinColumnName}',");
      buffer.writeln("          '${junction.inverseColumnName}',");
      buffer.writeln('        ],');
      buffer.writeln('      ),');
      buffer.writeln('    );');

      // Add indexes if needed
      if (junction.createIndex) {
        buffer.writeln();
        buffer.writeln(
          "    await createIndex(name: 'idx_${junction.tableName}_${junction.joinColumnName}', table: '${junction.tableName}', columns: ['${junction.joinColumnName}']);",
        );
        buffer.writeln(
          "    await createIndex(name: 'idx_${junction.tableName}_${junction.inverseColumnName}', table: '${junction.tableName}', columns: ['${junction.inverseColumnName}']);",
        );
      }
      buffer.writeln();
    }

    buffer.writeln('  }');
    buffer.writeln();

    // Generate down migration
    buffer.writeln('  @override');
    buffer.writeln('  Future<void> down() async {');

    // Drop junction tables first (they reference entity tables)
    for (final junction in junctionTables.reversed) {
      buffer.writeln("    await dropTable('${junction.tableName}');");
    }

    // Drop entity tables in reverse order
    for (final entity in entities.reversed) {
      buffer.writeln("    await dropTable('${entity.tableName}');");
    }

    buffer.writeln('  }');
    buffer.writeln('}');

    return buffer.toString();
  }

  String _generateMigrationExtension(String className, int migrationVersion) {
    return '''

/// Migration extension for $className
/// Provides access to generated migrations and validation
extension ${className}Migrations on $className {
  /// Get all generated migrations
  List<DatabaseMigration> get generatedMigrations => _${_toCamelCase(className)}GeneratedMigrations;

  /// Combine generated migrations with custom migrations
  /// 
  /// Throws [StateError] if a custom migration has the same version as a generated one
  /// 
  /// Example:
  /// ```dart
  /// await db.setup(
  ///   migrations: db.allMigrations([
  ///     MyCustomMigration(), // version 2
  ///     AnotherMigration(),  // version 3
  ///   ]),
  /// );
  /// ```
  List<DatabaseMigration> allMigrations([List<DatabaseMigration> customMigrations = const []]) {
    final generated = generatedMigrations;
    final generatedVersions = generated.map((m) => m.version).toSet();
    
    // Check for version conflicts
    for (final custom in customMigrations) {
      if (generatedVersions.contains(custom.version)) {
        throw StateError(
          'Migration version conflict: Custom migration has version \${custom.version} '
          'which conflicts with a generated migration. '
          'Please use a different version number for your custom migration.',
        );
      }
    }
    
    // Combine and sort by version
    final all = [...generated, ...customMigrations];
    all.sort((a, b) => a.version.compareTo(b.version));
    return all;
  }

  /// Validate that custom migrations don't conflict with generated ones
  /// 
  /// Returns a list of error messages, empty if no conflicts
  List<String> validateMigrations(List<DatabaseMigration> customMigrations) {
    final errors = <String>[];
    final generated = generatedMigrations;
    final generatedVersions = generated.map((m) => m.version).toSet();
    
    for (final custom in customMigrations) {
      if (generatedVersions.contains(custom.version)) {
        errors.add(
          'Version conflict: Custom migration "\${custom.description}" has version '
          '\${custom.version} which conflicts with generated migration.',
        );
      }
    }
    
    return errors;
  }
}
''';
  }

  String _relationActionToCode(String action) {
    switch (action) {
      case 'cascade':
        return ', onDelete: ForeignKeyAction.cascade';
      case 'restrict':
        return ', onDelete: ForeignKeyAction.restrict';
      case 'setNull':
        return ', onDelete: ForeignKeyAction.setNull';
      case 'setDefault':
        return ', onDelete: ForeignKeyAction.setDefault';
      case 'noAction':
      default:
        return '';
    }
  }

  /// Convert SQL type string to SQLType enum name
  SQLType _toSQLTypeEnum(String sqlType) {
    return SQLType.fromName(sqlType);
  }

  /// Get a sensible default value for a SQL type when adding a column
  /// For nullable columns, returns 'NULL'
  /// For NOT NULL columns, returns a sensible default based on type
  String _getDefaultValueForType(SQLType sqlType, bool nullable) {
    if (nullable) return 'NULL';

    switch (sqlType) {
      case SQLType.integer:
      case SQLType.bigint:
      case SQLType.smallint:
      case SQLType.serial:
      case SQLType.bigserial:
        return '0';
      case SQLType.real:
      case SQLType.doublePrecision:
      case SQLType.numeric:
      case SQLType.decimal:
        return '0.0';
      case SQLType.boolean:
        return 'false';
      case SQLType.text:
      case SQLType.varchar:
      case SQLType.char:
        return "";
      case SQLType.timestamp:
      case SQLType.timestamptz:
        return 'CURRENT_TIMESTAMP';
      case SQLType.date:
        return 'CURRENT_DATE';
      case SQLType.time:
      case SQLType.timetz:
        return 'CURRENT_TIME';
      case SQLType.interval:
        return "'0'";
      case SQLType.json:
      case SQLType.jsonb:
        return "'{}'";
      case SQLType.uuid:
        return "gen_random_uuid()";
      case SQLType.blob:
      case SQLType.bytea:
        return "";
    }
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
      if (index == 0) {
        dbType = 'postgresql';
      } else if (index == 1) {
        dbType = 'mysql';
      } else if (index == 2) {
        dbType = 'sqlite';
      }
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
          dartType: field.type.getDisplayString(),
          sqlType: sqlType,
          isNullable: isNullable,
          isPrimaryKey: isPrimaryKey,
        ),
      );
    }

    return columns;
  }

  /// Extract OneToMany relationships from entity
  List<_OneToManyInfo> _extractOneToManyRelations(
    ClassElement element,
    String ownerTableName,
    Map<String, String> entityToTableName,
  ) {
    final relations = <_OneToManyInfo>[];
    final targetEntityPattern = RegExp(r'targetEntity:\s*(\w+)');
    final onDeletePattern = RegExp(r'onDelete:\s*RelationAction\.(\w+)');
    final onUpdatePattern = RegExp(r'onUpdate:\s*RelationAction\.(\w+)');

    for (final field in element.fields) {
      if (field.isStatic) continue;

      for (final meta in field.metadata.annotations) {
        if (meta.element?.enclosingElement?.name == 'OneToMany') {
          final source = meta.toSource();

          final targetMatch = targetEntityPattern.firstMatch(source);
          if (targetMatch == null) continue;
          final targetEntityName = targetMatch.group(1)!;

          final targetTableName =
              entityToTableName[targetEntityName] ??
              _toSnakeCase(targetEntityName);

          final foreignKeyColumn = '${ownerTableName}_id';

          final onDeleteMatch = onDeletePattern.firstMatch(source);
          final onDelete = onDeleteMatch?.group(1) ?? 'noAction';

          final onUpdateMatch = onUpdatePattern.firstMatch(source);
          final onUpdate = onUpdateMatch?.group(1) ?? 'noAction';

          relations.add(
            _OneToManyInfo(
              ownerEntityName: element.name!,
              ownerTableName: ownerTableName,
              targetEntityName: targetEntityName,
              targetTableName: targetTableName,
              fieldName: field.name!,
              foreignKeyColumn: foreignKeyColumn,
              referencedColumn: 'id',
              onDelete: onDelete,
              onUpdate: onUpdate,
            ),
          );
        }
      }
    }

    return relations;
  }

  /// Extract ManyToOne relationships from entity
  List<_ManyToOneInfo> _extractManyToOneRelations(
    ClassElement element,
    String ownerTableName,
    Map<String, String> entityToTableName,
  ) {
    final relations = <_ManyToOneInfo>[];
    final targetEntityPattern = RegExp(r'targetEntity:\s*(\w+)');
    final foreignKeyPattern = RegExp(r'''foreignKey:\s*['"](\w+)['"]''');
    final referencedColumnPattern = RegExp(
      r'''referencedColumn:\s*['"](\w+)['"]''',
    );
    final nullablePattern = RegExp(r'nullable:\s*(true|false)');
    final onDeletePattern = RegExp(r'onDelete:\s*RelationAction\.(\w+)');
    final onUpdatePattern = RegExp(r'onUpdate:\s*RelationAction\.(\w+)');

    for (final field in element.fields) {
      if (field.isStatic) continue;

      for (final meta in field.metadata.annotations) {
        if (meta.element?.enclosingElement?.name == 'ManyToOne') {
          final source = meta.toSource();

          final targetMatch = targetEntityPattern.firstMatch(source);
          if (targetMatch == null) continue;
          final targetEntityName = targetMatch.group(1)!;

          final targetTableName =
              entityToTableName[targetEntityName] ??
              _toSnakeCase(targetEntityName);

          final fkMatch = foreignKeyPattern.firstMatch(source);
          final foreignKeyColumn = fkMatch?.group(1) ?? '${targetTableName}_id';

          final refColMatch = referencedColumnPattern.firstMatch(source);
          final referencedColumn = refColMatch?.group(1) ?? 'id';

          final nullableMatch = nullablePattern.firstMatch(source);
          final nullable = nullableMatch?.group(1) != 'false';

          final onDeleteMatch = onDeletePattern.firstMatch(source);
          final onDelete = onDeleteMatch?.group(1) ?? 'noAction';

          final onUpdateMatch = onUpdatePattern.firstMatch(source);
          final onUpdate = onUpdateMatch?.group(1) ?? 'noAction';

          relations.add(
            _ManyToOneInfo(
              ownerEntityName: element.name!,
              ownerTableName: ownerTableName,
              targetEntityName: targetEntityName,
              targetTableName: targetTableName,
              fieldName: field.name!,
              foreignKeyColumn: foreignKeyColumn,
              referencedColumn: referencedColumn,
              nullable: nullable,
              onDelete: onDelete,
              onUpdate: onUpdate,
            ),
          );
        }
      }
    }

    return relations;
  }

  /// Extract ManyToMany relationships from entity
  List<_ManyToManyInfo> _extractManyToManyRelations(
    ClassElement element,
    String ownerTableName,
    Map<String, ClassElement> entityElements,
    Map<String, String> entityToTableName,
  ) {
    final relations = <_ManyToManyInfo>[];
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

          final targetMatch = targetEntityPattern.firstMatch(source);
          if (targetMatch == null) continue;
          final targetEntityName = targetMatch.group(1)!;

          final mappedByMatch = mappedByPattern.firstMatch(source);
          final hasJoinTable = joinTablePattern.hasMatch(source);
          final isOwningSide = hasJoinTable || mappedByMatch == null;

          if (isOwningSide && mappedByMatch == null) {
            String joinTableName;
            String joinColumnName;
            String joinColumnRef;
            String inverseColumnName;
            String inverseColumnRef;
            bool createIndex = true;

            final targetTableName =
                entityToTableName[targetEntityName] ??
                _toSnakeCase(targetEntityName);

            final nameMatch = namePattern.firstMatch(source);
            if (nameMatch != null) {
              joinTableName = nameMatch.group(1)!;
            } else {
              joinTableName = '${ownerTableName}_$targetTableName';
            }

            joinColumnName = '${ownerTableName}_id';
            joinColumnRef = 'id';
            inverseColumnName = '${targetTableName}_id';
            inverseColumnRef = 'id';

            final indexMatch = createIndexPattern.firstMatch(source);
            if (indexMatch != null) {
              createIndex = indexMatch.group(1) == 'true';
            }

            relations.add(
              _ManyToManyInfo(
                ownerEntityName: element.name!,
                ownerTableName: ownerTableName,
                targetEntityName: targetEntityName,
                fieldName: field.name!,
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

  /// Deduplicate junction tables
  List<_JunctionTableInfo> _deduplicateJunctionTables(
    List<_ManyToManyInfo> relations,
    Map<String, String> entityToTableName,
  ) {
    final tables = <String, _JunctionTableInfo>{};

    for (final relation in relations.where((r) => r.isOwningSide)) {
      if (!tables.containsKey(relation.joinTableName)) {
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

    return tables.values.toList();
  }

  // ignore: deprecated_member_use
  String _getDartToSqlType(DartType type) {
    // ignore: deprecated_member_use
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

  String _toCamelCase(String text) {
    if (text.isEmpty) return text;
    return text[0].toLowerCase() + text.substring(1);
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
}

// Helper classes
class _EntityInfo {
  final String className;
  final String repositoryName;
  final String tableName;
  final List<_ColumnInfo> columns;
  final List<_ManyToOneInfo> manyToOneRelations;

  _EntityInfo({
    required this.className,
    required this.repositoryName,
    required this.tableName,
    required this.columns,
    this.manyToOneRelations = const [],
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

class _OneToManyInfo {
  final String ownerEntityName;
  final String ownerTableName;
  final String targetEntityName;
  final String targetTableName;
  final String fieldName;
  final String foreignKeyColumn;
  final String referencedColumn;
  final String onDelete;
  final String onUpdate;

  _OneToManyInfo({
    required this.ownerEntityName,
    required this.ownerTableName,
    required this.targetEntityName,
    required this.targetTableName,
    required this.fieldName,
    required this.foreignKeyColumn,
    required this.referencedColumn,
    required this.onDelete,
    required this.onUpdate,
  });
}

class _ManyToOneInfo {
  final String ownerEntityName;
  final String ownerTableName;
  final String targetEntityName;
  final String targetTableName;
  final String fieldName;
  final String foreignKeyColumn;
  final String referencedColumn;
  final bool nullable;
  final String onDelete;
  final String onUpdate;

  _ManyToOneInfo({
    required this.ownerEntityName,
    required this.ownerTableName,
    required this.targetEntityName,
    required this.targetTableName,
    required this.fieldName,
    required this.foreignKeyColumn,
    required this.referencedColumn,
    required this.nullable,
    required this.onDelete,
    required this.onUpdate,
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

/// Types of schema changes
enum _ChangeType {
  addTable,
  dropTable,
  addColumn,
  dropColumn,
  alterColumn,
  addJunctionTable,
  dropJunctionTable,
}

/// Represents a schema change
class _SchemaChange {
  final _ChangeType type;
  final String tableName;
  final String? columnName;
  final dynamic details;

  _SchemaChange({
    required this.type,
    required this.tableName,
    this.columnName,
    this.details,
  });
}

Builder migrationGeneratorBuilder(BuilderOptions options) {
  return PartBuilder(
    [MigrationGenerator()],
    '.migration.g.dart',
  );
}
