import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
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
    final dbType = _getDatabaseType(annotation);
    final dbName = annotation.peek('name')?.stringValue;

    // Extract entity types from annotation
    final entitiesReader = annotation.peek('entities');
    final entities = <_EntityInfo>[];

    if (entitiesReader != null && !entitiesReader.isNull) {
      final entityList = entitiesReader.listValue;
      for (final entityValue in entityList) {
        final typeValue = entityValue.toTypeValue();
        if (typeValue != null) {
          final entityElement = typeValue.element;
          if (entityElement is ClassElement && entityElement.name != null) {
            entities.add(
              _EntityInfo(
                className: entityElement.name!,
                repositoryName: '${entityElement.name}Repository',
              ),
            );
          }
        }
      }
    }

    return _generateDbCode(
      className: className!,
      entities: entities,
      migrationVersion: migrationVersion,
      dbType: dbType,
      dbName: dbName,
    );
  }

  String _getDatabaseType(ConstantReader annotation) {
    final dbTypeValue = annotation.peek('dbType')?.objectValue;
    if (dbTypeValue != null) {
      final index = dbTypeValue.getField('index')?.toIntValue();
      if (index == 0) return 'postgresql';
      if (index == 1) return 'mysql';
      if (index == 2) return 'sqlite';
    }
    return 'postgresql';
  }

  String _generateDbCode({
    required String className,
    required List<_EntityInfo> entities,
    required int migrationVersion,
    required String dbType,
    String? dbName,
  }) {
    final buffer = StringBuffer();

    // Header comment only - PartBuilder handles 'part of' directive
    buffer.writeln('// Generated database class for $className');
    buffer.writeln('// Migration version: $migrationVersion');
    buffer.writeln();

    // Generate singleton repository holders
    buffer.writeln(_generateRepositoryHolders(className, entities));

    // Generate repository extension for database class
    buffer.writeln(_generateRepositoryExtension(className, entities));

    return buffer.toString();
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

  String _toCamelCase(String text) {
    if (text.isEmpty) return text;
    return text[0].toLowerCase() + text.substring(1);
  }
}

class _EntityInfo {
  final String className;
  final String repositoryName;

  _EntityInfo({
    required this.className,
    required this.repositoryName,
  });
}

Builder dbGeneratorBuilder(BuilderOptions options) {
  return PartBuilder(
    [DbGenerator()],
    '.db.g.dart',
  );
}
