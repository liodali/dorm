import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:dorm/src/annotation.dart';
import 'package:source_gen/source_gen.dart';

class SchemaGenerator extends GeneratorForAnnotation<Entity> {
  @override
  Future<String> generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) async {
    final className = element.name;
    final tableName =
        annotation.peek('tableName')?.stringValue ?? _toTableName(className!);

    final schema = _generateSchema(element as ClassElement, tableName);

    return '''
// Generated schema for $className
final ${_toCamelCase(className!)}Schema = DatabaseSchema(
  tableName: '$tableName',
  columns: [
    $schema
  ],
);
    ''';
  }

  String _generateSchema(ClassElement element, String tableName) {
    final columns = <String>[];

    for (final field in element.fields) {
      if (field.isStatic) continue;

      final column = _readColumnAnnotation(field);
      if (column != null) {
        columns.add(column);
      }
    }

    return columns.join(',\n    ');
  }

  String? _readColumnAnnotation(FieldElement field) {
    // Parse and generate column definitions
    return '''ColumnSchema(
      name: '${_toSnakeCase(field.displayName)}',
      type: '${_getDartToSqlType(field.type)}',
      nullable: true,
      primaryKey: false,
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
}
