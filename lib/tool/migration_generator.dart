import 'dart:convert';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:crypto/crypto.dart';
import 'package:dorm/src/annotation.dart';
import 'package:source_gen/source_gen.dart';

/// Generator for database migrations
/// Generates migrations in .migration.g.dart as part of the database file
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

    // Generate schema hash
    final schemaHash = _generateSchemaHash(entities, junctionTables);

    return _generateMigrationCode(
      className: className!,
      entities: entities,
      junctionTables: junctionTables,
      migrationVersion: migrationVersion,
      sqlDialect: sqlDialect,
      schemaHash: schemaHash,
    );
  }

  String _generateMigrationCode({
    required String className,
    required List<_EntityInfo> entities,
    required List<_JunctionTableInfo> junctionTables,
    required int migrationVersion,
    required String sqlDialect,
    required String schemaHash,
  }) {
    final buffer = StringBuffer();

    // Header comment
    buffer.writeln('// Generated migrations for $className');
    buffer.writeln('// Migration version: $migrationVersion');
    buffer.writeln('// Schema hash: $schemaHash');
    buffer.writeln('// SQL Dialect: $sqlDialect');
    buffer.writeln();

    // Generate the migrations list getter
    buffer.writeln(_generateMigrationsGetter(className, migrationVersion));

    // Generate initial schema migration (version 1)
    buffer.writeln(
      _generateInitialMigration(
        className,
        entities,
        junctionTables,
        sqlDialect,
      ),
    );

    // Generate migration extension with validation
    buffer.writeln(_generateMigrationExtension(className, migrationVersion));

    return buffer.toString();
  }

  String _generateMigrationsGetter(String className, int migrationVersion) {
    return '''
/// Generated migrations for $className
/// These are auto-generated based on the schema definition
/// 
/// Usage:
/// ```dart
/// await db.setup(
///   migrations: db.generatedMigrations,
/// );
/// ```
/// 
/// Or combine with custom migrations:
/// ```dart
/// await db.setup(
///   migrations: db.allMigrations([
///     // Your custom migrations here
///     MyCustomMigration(),
///   ]),
/// );
/// ```
List<DatabaseMigration> get _${_toCamelCase(className)}GeneratedMigrations => [
  _${className}InitialMigration(),
];
''';
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
        buffer.writeln(
          "          ColumnSchema(name: '${column.name}', type: '${column.sqlType}'$nullableStr$pkStr),",
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
        "          ColumnSchema(name: '${junction.joinColumnName}', type: 'INTEGER'),",
      );
      buffer.writeln(
        "          ColumnSchema(name: '${junction.inverseColumnName}', type: 'INTEGER'),",
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

Builder migrationGeneratorBuilder(BuilderOptions options) {
  return PartBuilder(
    [MigrationGenerator()],
    '.migration.g.dart',
  );
}
