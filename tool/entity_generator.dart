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

      final columnAnnotation = _getAnnotation(field, 'Column');
      final idAnnotation = _getAnnotation(field, 'Id');
      final oneToMany = _getAnnotation(field, 'OneToMany');
      final manyToOne = _getAnnotation(field, 'ManyToOne');
      final manyToMany = _getAnnotation(field, 'ManyToMany');

      if (oneToMany != null || manyToOne != null || manyToMany != null) {
        relationships.add({
          'fieldName': field.name,
          'type': _getRelationType(field),
          'annotation': oneToMany ?? manyToOne ?? manyToMany,
        });
        continue;
      }

      if (columnAnnotation != null || idAnnotation != null) {
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
    }

    final code = _generateRepositoryCode(
      className!,
      tableName,
      fields,
      relationships,
      dbType,
    );

    // Return the generated code
    return code;
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

    return '''
// Generated code for $className
part of '${_snakeCase(className)}.dart';

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
}
    ''';
  }

  String _getColumnName(FieldElement field, ElementAnnotation? annotation) {
    if (annotation != null) {
      // Try to get column name from annotation
      // This is simplified - in real implementation, parse the annotation
    }
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
        conversion = '$value';
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
}
