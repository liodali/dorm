import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:dorm/src/annotation.dart';
import 'package:source_gen/source_gen.dart';

class MigrationGenerator extends GeneratorForAnnotation<Migration> {
  @override
  Future<String> generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) async {
    final version = annotation.peek('version')?.intValue ?? 1;
    final description = annotation.peek('description')?.stringValue ?? '';

    return '''
class Migration_$version extends DatabaseMigration {
  @override
  int get version => $version;

  @override
  String get description => '$description';

  @override
  Future<void> up(Database db) async {
    // Generated migration up
  }

  @override
  Future<void> down(Database db) async {
    // Generated migration down
  }
}
    ''';
  }
}
