import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:collection/collection.dart';
import 'package:dorm/src/annotation.dart';
import 'package:source_gen/source_gen.dart';

/// Generator for @Db annotation - generates db.schemas.g.dart
/// Contains all entity schemas and junction table schemas for the database
class DbSchemaGenerator extends GeneratorForAnnotation<Db> {
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

    // Extract entity types from annotation
    final entitiesReader = annotation.peek('entities');
    final entities = <_EntitySchemaInfo>[];
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

            // Extract ManyToMany relationships
            final m2mRelations = _extractManyToManyRelations(
              entityElement,
              tableName,
              entityElements,
              entityToTableName,
            );
            manyToManyRelations.addAll(m2mRelations);

            // Generate full entity schema info
            final schemaInfo = _extractEntitySchemaInfo(
              entityElement,
              tableName,
            );
            entities.add(schemaInfo);
          }
        }
      }
    }

    // Deduplicate junction tables (keep only owning side)
    final junctionTables = _deduplicateJunctionTables(
      manyToManyRelations,
      entityToTableName,
    );

    return _generateSchemaCode(
      className: className!,
      entities: entities,
      junctionTables: junctionTables,
    );
  }

  /// Extract full schema info from an entity class
  _EntitySchemaInfo _extractEntitySchemaInfo(
    ClassElement element,
    String tableName,
  ) {
    final className = element.name!;
    final fieldNames = _collectFieldNames(element);

    // Validate class-level annotations
    _validateClassAnnotations(element, fieldNames);

    final columns = _extractColumns(element);
    final indexes = _extractIndexes(element, tableName);
    final foreignKeys = _extractForeignKeys(element);
    final primaryKeyColumns = _extractPrimaryKeyColumns(element);
    final uniqueConstraints = _extractUniqueConstraints(element);
    final checkConstraints = _extractCheckConstraints(element);

    return _EntitySchemaInfo(
      className: className,
      tableName: tableName,
      columns: columns,
      indexes: indexes,
      foreignKeys: foreignKeys,
      primaryKeyColumns: primaryKeyColumns,
      uniqueConstraints: uniqueConstraints,
      checkConstraints: checkConstraints,
    );
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
        _validateColumnsExist(annotation, 'PrimaryKey', fieldNames, element);
      } else if (annotationName == 'Unique') {
        final columns = _getAnnotationListValue(annotation, 'columns');
        if (columns != null && columns.isNotEmpty) {
          _validateColumnsExist(annotation, 'Unique', fieldNames, element);
        }
      } else if (annotationName == 'Index') {
        _validateColumnsExist(annotation, 'Index', fieldNames, element);
      }
    }
  }

  /// Validate that all columns in an annotation exist in the entity
  void _validateColumnsExist(
    ElementAnnotation annotation,
    String annotationName,
    Set<String> fieldNames,
    ClassElement element,
  ) {
    final columns = _getAnnotationListValue(annotation, 'columns');
    if (columns == null) return;

    for (final column in columns) {
      final columnName = column.toStringValue();
      if (columnName != null && !fieldNames.contains(columnName)) {
        throw InvalidGenerationSourceError(
          '@$annotationName references column "$columnName" which does not exist. '
          'Available columns: ${fieldNames.join(', ')}',
          element: element,
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

  /// Extract columns from entity
  List<_ColumnInfo> _extractColumns(ClassElement element) {
    final columns = <_ColumnInfo>[];

    for (final field in element.fields) {
      if (field.isStatic) continue;
      if (_isRelationshipField(field)) continue;
      if (_hasAnnotation(field, 'Ignore')) continue;

      final isUnique = _hasAnnotation(field, 'Unique');
      final isId = _hasAnnotation(field, 'Id');
      final isNullable =
          !isId && field.type.nullabilitySuffix.toString().contains('question');

      columns.add(
        _ColumnInfo(
          name: _toSnakeCase(field.displayName),
          type: _getDartToSqlType(field.type),
          nullable: isNullable,
          primaryKey: isId,
          unique: isUnique,
        ),
      );
    }

    return columns;
  }

  /// Extract indexes from @Index annotations
  List<_IndexInfo> _extractIndexes(ClassElement element, String tableName) {
    final indexes = <_IndexInfo>[];

    for (final annotation in element.metadata.annotations) {
      if (annotation.element?.enclosingElement?.name == 'Index') {
        final value = annotation.computeConstantValue();
        if (value == null) continue;

        final columns = value.getField('columns')?.toListValue();
        if (columns == null || columns.isEmpty) continue;

        final columnNames = columns.map((c) => c.toStringValue()!).toList();
        final name =
            value.getField('name')?.toStringValue() ??
            'idx_${tableName}_${columnNames.join('_')}';
        final unique = value.getField('unique')?.toBoolValue() ?? false;

        indexes.add(
          _IndexInfo(
            name: name,
            columns: columnNames,
            unique: unique,
          ),
        );
      }
    }

    return indexes;
  }

  /// Extract foreign keys from fields
  List<_ForeignKeyInfo> _extractForeignKeys(ClassElement element) {
    final foreignKeys = <_ForeignKeyInfo>[];

    for (final field in element.fields) {
      if (field.isStatic) continue;
      if (_isRelationshipField(field)) continue;
      if (_hasAnnotation(field, 'Ignore')) continue;

      // Check for ForeignKeyConstraint annotation
      final fkAnnotation = _getFieldAnnotation(field, 'ForeignKeyConstraint');
      if (fkAnnotation != null) {
        final value = fkAnnotation.computeConstantValue();
        if (value != null) {
          final column =
              value.getField('column')?.toStringValue() ??
              _toSnakeCase(field.displayName);
          final referencedTable = value
              .getField('referencedTable')
              ?.toStringValue();
          final referencedColumn =
              value.getField('referencedColumn')?.toStringValue() ?? 'id';

          if (referencedTable != null) {
            foreignKeys.add(
              _ForeignKeyInfo(
                column: column,
                referencedTable: referencedTable,
                referencedColumn: referencedColumn,
              ),
            );
          }
        }
      }
      // Auto-detect foreign key (ends with Id or _id)
      else if (field.displayName.endsWith('Id') ||
          field.displayName.endsWith('_id')) {
        final refTable = _inferReferencedTable(field.displayName);
        foreignKeys.add(
          _ForeignKeyInfo(
            column: _toSnakeCase(field.displayName),
            referencedTable: refTable,
            referencedColumn: 'id',
          ),
        );
      }
    }

    return foreignKeys;
  }

  /// Extract primary key columns from @PrimaryKey annotation
  List<String> _extractPrimaryKeyColumns(ClassElement element) {
    for (final annotation in element.metadata.annotations) {
      if (annotation.element?.enclosingElement?.name == 'PrimaryKey') {
        final value = annotation.computeConstantValue();
        final columns = value?.getField('columns')?.toListValue();
        if (columns != null && columns.isNotEmpty) {
          return columns.map((c) => c.toStringValue()!).toList();
        }
      }
    }
    return [];
  }

  /// Extract unique constraints from class-level @Unique annotations
  List<_UniqueConstraintInfo> _extractUniqueConstraints(ClassElement element) {
    final constraints = <_UniqueConstraintInfo>[];

    for (final annotation in element.metadata.annotations) {
      if (annotation.element?.enclosingElement?.name == 'Unique') {
        final value = annotation.computeConstantValue();
        final columns = value?.getField('columns')?.toListValue();
        if (columns != null && columns.isNotEmpty) {
          final columnNames = columns.map((c) => c.toStringValue()!).toList();
          final name = value?.getField('name')?.toStringValue();
          constraints.add(
            _UniqueConstraintInfo(
              columns: columnNames,
              name: name,
            ),
          );
        }
      }
    }

    return constraints;
  }

  /// Extract check constraints from @Check annotations
  List<_CheckConstraintInfo> _extractCheckConstraints(ClassElement element) {
    final constraints = <_CheckConstraintInfo>[];

    for (final field in element.fields) {
      if (field.isStatic) continue;

      final checkAnnotation = _getFieldAnnotation(field, 'Check');
      if (checkAnnotation != null) {
        final value = checkAnnotation.computeConstantValue();
        final expression = value?.getField('expression')?.toStringValue();
        final name = value?.getField('name')?.toStringValue();
        if (expression != null) {
          constraints.add(
            _CheckConstraintInfo(
              expression: expression,
              name: name,
            ),
          );
        }
      }
    }

    return constraints;
  }

  /// Get a specific annotation from a field
  ElementAnnotation? _getFieldAnnotation(FieldElement field, String name) {
    return field.metadata.annotations.firstWhereOrNull(
      (a) => a.element?.enclosingElement?.name == name,
    );
  }

  /// Check if a field has a relationship annotation
  bool _isRelationshipField(FieldElement field) {
    return _hasAnnotation(field, 'OneToOne') ||
        _hasAnnotation(field, 'OneToMany') ||
        _hasAnnotation(field, 'ManyToOne') ||
        _hasAnnotation(field, 'ManyToMany');
  }

  /// Check if a field has a specific annotation
  bool _hasAnnotation(FieldElement field, String annotationName) {
    return field.metadata.annotations.firstWhereOrNull(
          (a) => a.element?.enclosingElement?.name == annotationName,
        ) !=
        null;
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

  String _inferReferencedTable(String fieldName) {
    String tableName = fieldName;
    if (tableName.endsWith('Id')) {
      tableName = tableName.substring(0, tableName.length - 2);
    } else if (tableName.endsWith('_id')) {
      tableName = tableName.substring(0, tableName.length - 3);
    }
    return '${_toSnakeCase(tableName)}s';
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

            // Get target table name from map or fallback to snake_case
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
                mappedBy: mappedByMatch?.group(1),
                createIndex: false,
              ),
            );
          }
        }
      }
    }

    return relations;
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

  String _generateSchemaCode({
    required String className,
    required List<_EntitySchemaInfo> entities,
    required List<_JunctionTableInfo> junctionTables,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('// Generated schema definitions for $className');
    buffer.writeln('// Contains all entity schemas and junction table schemas');
    buffer.writeln();

    // Generate each entity schema
    for (final entity in entities) {
      buffer.writeln(_generateEntitySchema(entity));
    }

    // Generate entity schema list
    buffer.writeln('/// All entity schemas for this database');
    final schemaRefs = entities
        .map((e) => '_${_toCamelCase(e.className)}Schema')
        .join(',\n  ');
    buffer.writeln(
      'final _${_toCamelCase(className)}EntitySchemas = <DatabaseSchema>[',
    );
    buffer.writeln('  $schemaRefs,');
    buffer.writeln('];');
    buffer.writeln();

    // Generate junction table schemas
    if (junctionTables.isNotEmpty) {
      for (final j in junctionTables) {
        buffer.writeln(_generateJunctionSchema(j));
      }
    }

    // Generate junction schemas list
    buffer.writeln(
      '/// All junction table schemas for ManyToMany relationships',
    );
    final junctionSchemaRefs = junctionTables
        .map((j) => '_${_toCamelCase(j.tableName)}Schema')
        .join(',\n  ');
    buffer.writeln(
      'final _${_toCamelCase(className)}JunctionSchemas = <DatabaseSchema>[',
    );
    if (junctionTables.isNotEmpty) {
      buffer.writeln('  $junctionSchemaRefs,');
    }
    buffer.writeln('];');
    buffer.writeln();

    // Generate extension with getters
    buffer.writeln('/// Schema access extension for $className');
    buffer.writeln('extension ${className}Schemas on $className {');
    buffer.writeln('  /// Get all entity schemas for this database');
    buffer.writeln(
      '  List<DatabaseSchema> get databaseSchemas => _${_toCamelCase(className)}EntitySchemas;',
    );
    buffer.writeln();
    buffer.writeln('  /// Get all junction table schemas for this database');
    buffer.writeln(
      '  List<DatabaseSchema> get databaseJunctionSchemas => _${_toCamelCase(className)}JunctionSchemas;',
    );
    buffer.writeln();
    buffer.writeln(
      '  /// Get all schemas (entities + junctions) for this database',
    );
    buffer.writeln('  List<DatabaseSchema> get allSchemas => [');
    buffer.writeln('    ...databaseSchemas,');
    buffer.writeln('    ...databaseJunctionSchemas,');
    buffer.writeln('  ];');
    buffer.writeln('}');
    buffer.writeln();

    // Generate per-entity schema extensions for backward compatibility
    for (final entity in entities) {
      buffer.writeln('/// Schema extension for ${entity.className}');
      buffer.writeln(
        'extension ${entity.className}Schema on ${entity.className} {',
      );
      buffer.writeln('  /// Get the database schema for this entity');
      buffer.writeln(
        '  static DatabaseSchema get schema => _${_toCamelCase(entity.className)}Schema;',
      );
      buffer.writeln();
      buffer.writeln('  /// Table name for this entity');
      buffer.writeln("  static String get tableName => '${entity.tableName}';");
      buffer.writeln('}');
      buffer.writeln();
    }

    return buffer.toString();
  }

  String _generateEntitySchema(_EntitySchemaInfo entity) {
    final buffer = StringBuffer();

    buffer.writeln('/// Generated schema for ${entity.className}');
    buffer.writeln(
      'const _${_toCamelCase(entity.className)}Schema = DatabaseSchema(',
    );
    buffer.writeln("  tableName: '${entity.tableName}',");
    buffer.writeln('  columns: [');

    for (final col in entity.columns) {
      buffer.writeln('    ColumnSchema(');
      buffer.writeln("      name: '${col.name}',");
      buffer.writeln("      type: '${col.type}',");
      buffer.writeln('      nullable: ${col.nullable},');
      buffer.writeln('      primaryKey: ${col.primaryKey},');
      buffer.writeln('      unique: ${col.unique},');
      buffer.writeln('    ),');
    }

    buffer.writeln('  ],');

    // Indexes
    if (entity.indexes.isNotEmpty) {
      buffer.writeln('  indexes: [');
      for (final idx in entity.indexes) {
        final cols = idx.columns.map((c) => "'$c'").join(', ');
        buffer.writeln(
          "    IndexSchema(name: '${idx.name}', columns: [$cols], unique: ${idx.unique}),",
        );
      }
      buffer.writeln('  ],');
    }

    // Foreign keys
    if (entity.foreignKeys.isNotEmpty) {
      buffer.writeln('  foreignKeys: [');
      for (final fk in entity.foreignKeys) {
        buffer.writeln(
          "    ForeignKey(column: '${fk.column}', referencedTable: '${fk.referencedTable}', referencedColumn: '${fk.referencedColumn}'),",
        );
      }
      buffer.writeln('  ],');
    }

    // Primary key columns
    if (entity.primaryKeyColumns.isNotEmpty) {
      final cols = entity.primaryKeyColumns.map((c) => "'$c'").join(', ');
      buffer.writeln('  primaryKeyColumns: [$cols],');
    }

    // Unique constraints
    if (entity.uniqueConstraints.isNotEmpty) {
      buffer.writeln('  uniqueConstraints: [');
      for (final uc in entity.uniqueConstraints) {
        final cols = uc.columns.map((c) => "'$c'").join(', ');
        final nameParam = uc.name != null ? ", name: '${uc.name}'" : '';
        buffer.writeln("    UniqueConstraint(columns: [$cols]$nameParam),");
      }
      buffer.writeln('  ],');
    }

    // Check constraints
    if (entity.checkConstraints.isNotEmpty) {
      buffer.writeln('  checkConstraints: [');
      for (final cc in entity.checkConstraints) {
        final nameParam = cc.name != null ? ", name: '${cc.name}'" : '';
        buffer.writeln(
          "    CheckConstraint(expression: '${cc.expression}'$nameParam),",
        );
      }
      buffer.writeln('  ],');
    }

    buffer.writeln(');');
    buffer.writeln();

    return buffer.toString();
  }

  String _generateJunctionSchema(_JunctionTableInfo j) {
    final buffer = StringBuffer();

    buffer.writeln(
      '/// Junction table schema for ${j.ownerTableName} <-> ${j.targetTableName}',
    );
    buffer.writeln(
      'const _${_toCamelCase(j.tableName)}Schema = DatabaseSchema(',
    );
    buffer.writeln("  tableName: '${j.tableName}',");
    buffer.writeln('  columns: [');
    buffer.writeln(
      "    ColumnSchema(name: '${j.joinColumnName}', type: 'INTEGER', nullable: false, primaryKey: false),",
    );
    buffer.writeln(
      "    ColumnSchema(name: '${j.inverseColumnName}', type: 'INTEGER', nullable: false, primaryKey: false),",
    );
    buffer.writeln('  ],');
    buffer.writeln(');');
    buffer.writeln();

    return buffer.toString();
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
}

// Data classes

class _EntitySchemaInfo {
  final String className;
  final String tableName;
  final List<_ColumnInfo> columns;
  final List<_IndexInfo> indexes;
  final List<_ForeignKeyInfo> foreignKeys;
  final List<String> primaryKeyColumns;
  final List<_UniqueConstraintInfo> uniqueConstraints;
  final List<_CheckConstraintInfo> checkConstraints;

  _EntitySchemaInfo({
    required this.className,
    required this.tableName,
    required this.columns,
    required this.indexes,
    required this.foreignKeys,
    required this.primaryKeyColumns,
    required this.uniqueConstraints,
    required this.checkConstraints,
  });
}

class _ColumnInfo {
  final String name;
  final String type;
  final bool nullable;
  final bool primaryKey;
  final bool unique;

  _ColumnInfo({
    required this.name,
    required this.type,
    required this.nullable,
    required this.primaryKey,
    required this.unique,
  });
}

class _IndexInfo {
  final String name;
  final List<String> columns;
  final bool unique;

  _IndexInfo({
    required this.name,
    required this.columns,
    required this.unique,
  });
}

class _ForeignKeyInfo {
  final String column;
  final String referencedTable;
  final String referencedColumn;

  _ForeignKeyInfo({
    required this.column,
    required this.referencedTable,
    required this.referencedColumn,
  });
}

class _UniqueConstraintInfo {
  final List<String> columns;
  final String? name;

  _UniqueConstraintInfo({
    required this.columns,
    this.name,
  });
}

class _CheckConstraintInfo {
  final String expression;
  final String? name;

  _CheckConstraintInfo({
    required this.expression,
    this.name,
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

Builder dbSchemaGeneratorBuilder(BuilderOptions options) {
  return PartBuilder(
    [DbSchemaGenerator()],
    '.schemas.g.dart',
  );
}
