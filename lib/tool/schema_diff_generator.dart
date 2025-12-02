import 'dart:io';
import 'dart:convert';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:dartorm/src/annotation.dart';
import 'package:dartorm/src/database/database_connection.dart';
import 'package:source_gen/source_gen.dart';

/// Schema difference detector and migration generator
class SchemaDiffGenerator extends GeneratorForAnnotation<Entity> {
  @override
  Future<String> generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) async {
    if (element is! ClassElement) {
      return '';
    }

    final className = element.name;
    final tableName =
        annotation.peek('tableName')?.stringValue ?? _toSnakeCase(className!);
    final dbType = _getDatabaseType(annotation);

    // Get the package root directory from the input path
    final inputPath = buildStep.inputId.path;
    final packageRoot = inputPath.split('lib/').first;

    final helper = _SchemaDiffHelper(
      schemaFilePath: '$packageRoot.dorm/schemas',
      migrationsPath: '$packageRoot.dorm/migrations',
    );

    final migrationCode = await helper.generateMigrationIfNeeded(
      element,
      tableName,
      dbType,
    );

    return migrationCode ?? '';
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

  String _toSnakeCase(String text) {
    return text
        .replaceAllMapped(
          RegExp('[A-Z]'),
          (m) => '_${m.group(0)!.toLowerCase()}',
        )
        .replaceFirst(RegExp('^_'), '');
  }
}

/// Helper class for schema diff operations
class _SchemaDiffHelper {
  final String schemaFilePath;
  final String migrationsPath;

  _SchemaDiffHelper({
    required this.schemaFilePath,
    required this.migrationsPath,
  });

  /// Generate migration if schema has changed
  Future<String?> generateMigrationIfNeeded(
    ClassElement element,
    String tableName,
    DatabaseType dbType,
  ) async {
    final currentSchema = _extractSchemaFromElement(element, tableName);
    final previousSchema = await _loadPreviousSchema(tableName);

    if (previousSchema == null) {
      // First time - create initial migration and save schema
      await _saveSchema(currentSchema);
      return _generateInitialMigration(currentSchema, dbType);
    }

    final diff = _compareSchemas(previousSchema, currentSchema);
    if (diff.isEmpty) {
      return null; // No changes
    }

    // Generate migration for changes and save updated schema
    await _saveSchema(currentSchema);
    return _generateDiffMigration(diff, currentSchema, dbType);
  }

  Map<String, dynamic> _extractSchemaFromElement(
    ClassElement element,
    String tableName,
  ) {
    final columns = <Map<String, dynamic>>[];
    final foreignKeys = <Map<String, String>>[];
    final indexes = <Map<String, dynamic>>[];

    for (final field in element.fields) {
      if (field.isStatic) continue;

      // Check annotations
      bool hasIgnore = false;
      bool hasRelationship = false;
      bool isPrimaryKey = false;
      bool isUnique = false;
      String? defaultValue;

      for (final annotation in field.metadata.annotations) {
        final name = annotation.element?.enclosingElement?.name;
        if (name == 'Ignore') {
          hasIgnore = true;
          break;
        }
        if (name == 'OneToOne' ||
            name == 'ManyToOne' ||
            name == 'OneToMany' ||
            name == 'ManyToMany') {
          hasRelationship = true;
          break;
        }
        if (name == 'Id') {
          isPrimaryKey = true;
        }
        if (name == 'Column') {
          // Parse column properties from annotation
          final source = annotation.toSource();
          isUnique = source.contains('unique: true');
        }
        if (name == 'Index') {
          // Extract index information
          indexes.add({
            'columns': [field.name],
            'unique': false,
          });
        }
      }

      if (hasIgnore || hasRelationship) continue;

      final fieldName = field.name;
      if (fieldName == null) continue;

      final columnName = _toSnakeCase(fieldName);
      final sqlType = _dartTypeToSql(
        field.type.getDisplayString().replaceAll('?', ''),
      );

      // Determine nullability from field type
      // A field is nullable if its Dart type is nullable (e.g., String?)
      final typeIsNullable = field.type.nullabilitySuffix.toString().contains(
        'question',
      );
      // Primary keys are never nullable, otherwise use type nullability
      final finalNullable = isPrimaryKey ? false : typeIsNullable;

      columns.add({
        'name': columnName,
        'type': sqlType,
        'nullable': finalNullable,
        'primaryKey': isPrimaryKey,
        'unique': isUnique,
        'defaultValue': defaultValue,
      });

      // Detect foreign keys
      if (fieldName.endsWith('Id') || fieldName.endsWith('_id')) {
        final refTable = _inferReferencedTable(fieldName);
        foreignKeys.add({
          'column': columnName,
          'referencedTable': refTable,
          'referencedColumn': 'id',
        });
      }
    }

    return {
      'tableName': tableName,
      'columns': columns,
      'foreignKeys': foreignKeys,
      'indexes': indexes,
    };
  }

  Future<Map<String, dynamic>?> _loadPreviousSchema(String tableName) async {
    final file = File('$schemaFilePath/$tableName.schema.json');
    if (!await file.exists()) {
      return null;
    }

    final content = await file.readAsString();
    return json.decode(content) as Map<String, dynamic>;
  }

  Future<void> _saveSchema(Map<String, dynamic> schema) async {
    final tableName = schema['tableName'];
    final file = File('$schemaFilePath/$tableName.schema.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(json.encode(schema));
  }

  List<Map<String, dynamic>> _compareSchemas(
    Map<String, dynamic> oldSchema,
    Map<String, dynamic> newSchema,
  ) {
    final changes = <Map<String, dynamic>>[];

    final oldColumns = Map.fromEntries(
      (oldSchema['columns'] as List).map((c) => MapEntry(c['name'], c)),
    );
    final newColumns = Map.fromEntries(
      (newSchema['columns'] as List).map((c) => MapEntry(c['name'], c)),
    );

    // Detect added columns
    for (final entry in newColumns.entries) {
      if (!oldColumns.containsKey(entry.key)) {
        changes.add({
          'type': 'ADD_COLUMN',
          'column': entry.value,
        });
      }
    }

    // Detect removed columns
    for (final entry in oldColumns.entries) {
      if (!newColumns.containsKey(entry.key)) {
        changes.add({
          'type': 'DROP_COLUMN',
          'columnName': entry.key,
        });
      }
    }

    // Detect modified columns
    for (final entry in newColumns.entries) {
      if (oldColumns.containsKey(entry.key)) {
        final oldCol = oldColumns[entry.key]!;
        final newCol = entry.value;

        if (oldCol['type'] != newCol['type'] ||
            oldCol['nullable'] != newCol['nullable'] ||
            oldCol['unique'] != newCol['unique']) {
          changes.add({
            'type': 'ALTER_COLUMN',
            'oldColumn': oldCol,
            'newColumn': newCol,
          });
        }
      }
    }

    return changes;
  }

  String _generateInitialMigration(
    Map<String, dynamic> schema,
    DatabaseType dbType,
  ) {
    final tableName = schema['tableName'];
    final columns = schema['columns'] as List;
    final foreignKeys = schema['foreignKeys'] as List;
    final version = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final columnDefs = columns
        .map((col) {
          final parts = <String>[];
          parts.add('${col['name']} ${col['type']}');

          if (col['primaryKey'] == true) {
            parts.add('PRIMARY KEY');
            if (dbType == DatabaseType.postgresql) {
              // Use SERIAL for auto-increment
              parts[0] = '${col['name']} SERIAL PRIMARY KEY';
              return parts[0];
            }
          }

          if (col['nullable'] == false) {
            parts.add('NOT NULL');
          }

          if (col['unique'] == true) {
            parts.add('UNIQUE');
          }

          if (col['defaultValue'] != null) {
            parts.add("DEFAULT ${col['defaultValue']}");
          }

          return parts.join(' ');
        })
        .join(',\n        ');

    final fkConstraints = foreignKeys
        .map((fk) {
          return 'FOREIGN KEY (${fk['column']}) REFERENCES ${fk['referencedTable']}(${fk['referencedColumn']})';
        })
        .join(',\n        ');

    final allConstraints = fkConstraints.isNotEmpty
        ? '$columnDefs,\n        $fkConstraints'
        : columnDefs;

    return '''
// Generated migration for $tableName
class Migration${version}_Create${_toPascalCase(tableName)} extends DatabaseMigration {
  @override
  int get version => $version;

  @override
  String get description => 'Create $tableName table';

  @override
  DatabaseType get dbType => DatabaseType.${dbType.name};

  @override
  Future<void> Up() async {
    const sql = \'\'\'
      CREATE TABLE IF NOT EXISTS $tableName (
        $allConstraints
      );
    \'\'\';

    await connection.execute(sql);
  }

  @override
  Future<void> Down() async {
    const sql = 'DROP TABLE IF EXISTS $tableName CASCADE;';
    await connection.execute(sql);
  }
}
''';
  }

  String _generateDiffMigration(
    List<Map<String, dynamic>> changes,
    Map<String, dynamic> schema,
    DatabaseType dbType,
  ) {
    final tableName = schema['tableName'];
    final version = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final upStatements = <String>[];
    final downStatements = <String>[];

    for (final change in changes) {
      switch (change['type']) {
        case 'ADD_COLUMN':
          final col = change['column'];
          final colDef =
              '${col['name']} ${col['type']}${col['nullable'] == false ? ' NOT NULL' : ''}';
          upStatements.add("ALTER TABLE $tableName ADD COLUMN $colDef;");
          downStatements.add(
            "ALTER TABLE $tableName DROP COLUMN ${col['name']};",
          );
          break;

        case 'DROP_COLUMN':
          final colName = change['columnName'];
          upStatements.add("ALTER TABLE $tableName DROP COLUMN $colName;");
          // Note: Cannot easily restore dropped column in down migration
          downStatements.add("-- Cannot restore dropped column $colName");
          break;

        case 'ALTER_COLUMN':
          final newCol = change['newColumn'];
          final colName = newCol['name'];
          if (dbType == DatabaseType.postgresql) {
            upStatements.add(
              "ALTER TABLE $tableName ALTER COLUMN $colName TYPE ${newCol['type']};",
            );
          } else {
            upStatements.add(
              "ALTER TABLE $tableName MODIFY COLUMN $colName ${newCol['type']};",
            );
          }
          break;
      }
    }

    final upSql = upStatements.join('\n      ');
    final downSql = downStatements.reversed.join('\n      ');

    return '''
// Generated migration for $tableName changes
class Migration${version}_Update${_toPascalCase(tableName)} extends DatabaseMigration {
  @override
  int get version => $version;

  @override
  String get description => 'Update $tableName table schema';

  @override
  DatabaseType get dbType => DatabaseType.${dbType.name};

  @override
  Future<void> Up() async {
    await connection.execute(\'\'\'
      $upSql
    \'\'\');
  }

  @override
  Future<void> Down() async {
    await connection.execute(\'\'\'
      $downSql
    \'\'\');
  }
}
''';
  }

  String _dartTypeToSql(String dartType) {
    const typeMap = {
      'String': 'VARCHAR(255)',
      'int': 'INTEGER',
      'double': 'DOUBLE PRECISION',
      'bool': 'BOOLEAN',
      'DateTime': 'TIMESTAMP',
    };
    return typeMap[dartType] ?? 'TEXT';
  }

  String _toSnakeCase(String text) {
    return text
        .replaceAllMapped(
          RegExp('[A-Z]'),
          (m) => '_${m.group(0)!.toLowerCase()}',
        )
        .replaceFirst(RegExp('^_'), '');
  }

  String _toPascalCase(String text) {
    return text
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join('');
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
}

Builder schemaDiffGeneratorBuilder(BuilderOptions options) =>
    LibraryBuilder(SchemaDiffGenerator(), generatedExtension: '.diff.g.dart');
