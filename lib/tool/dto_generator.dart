import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:build/build.dart';
import 'package:collection/collection.dart';
import 'package:dormql/src/annotation.dart';
import 'package:source_gen/source_gen.dart';

/// Generator for DTOs (Data Transfer Objects)
/// Generates DTOs for all @Entity classes automatically
class DtoGenerator extends GeneratorForAnnotation<Entity> {
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
    final dtoClassName = '${className}Dto';

    // Extract only primitive fields (exclude relationships)
    final primitiveFields = <Map<String, dynamic>>[];

    for (final field in element.fields) {
      if (field.isStatic) continue;

      // Skip ignored fields
      final ignoreAnnotation = _getAnnotation(field, 'Ignore');
      if (ignoreAnnotation != null) continue;

      // Skip relationship fields
      final oneToOne = _getAnnotation(field, 'OneToOne');
      final oneToMany = _getAnnotation(field, 'OneToMany');
      final manyToOne = _getAnnotation(field, 'ManyToOne');
      final manyToMany = _getAnnotation(field, 'ManyToMany');

      if (oneToOne != null ||
          oneToMany != null ||
          manyToOne != null ||
          manyToMany != null) {
        continue; // Skip relationship fields
      }

      // Include primitive fields
      final isNullable =
          field.type.nullabilitySuffix == NullabilitySuffix.question;
      primitiveFields.add({
        'name': field.name,
        'type': field.type.getDisplayString(),
        'isNullable': isNullable,
      });
    }

    // If there are no primitive fields, don't generate a DTO
    if (primitiveFields.isEmpty) {
      return '';
    }

    // Get source file path for part of directive
    final sourceFilePath = buildStep.inputId.path;
    final entityFileName = _getEntityFileName(sourceFilePath);

    return _generateDtoCode(
      className!,
      dtoClassName,
      primitiveFields,
      entityFileName,
    );
  }

  ElementAnnotation? _getAnnotation(FieldElement field, String name) {
    return field.metadata.annotations.firstWhereOrNull(
      (a) => a.element?.enclosingElement?.name == name,
    );
  }

  String _getEntityFileName(String inputPath) {
    // Extract just the file name from the full path
    // Example: lib/src/models/user_entity.dart -> user_entity.dart
    return inputPath.split('/').last;
  }

  String _generateDtoCode(
    String entityClassName,
    String dtoClassName,
    List<Map<String, dynamic>> fields,
    String entityFileName,
  ) {
    // Generate field declarations
    final fieldDeclarations = fields
        .map((f) {
          return '  final ${f['type']} ${f['name']};';
        })
        .join('\n');

    // Generate constructor parameters
    final constructorParams = fields
        .map((f) {
          final isRequired = !f['isNullable'];
          final prefix = isRequired ? 'required ' : '';
          return '    ${prefix}this.${f['name']},';
        })
        .join('\n');

    // Generate fromEntity factory
    final fromEntityMappings = fields
        .map((f) {
          return '      ${f['name']}: entity.${f['name']},';
        })
        .join('\n');

    // Generate toEntity method mappings
    final toEntityMappings = fields
        .map((f) {
          return '      ${f['name']}: ${f['name']},';
        })
        .join('\n');

    // Generate copyWith method - make parameters nullable without double ?
    final copyWithParams = fields
        .map((f) {
          final type = f['type'] as String;
          // If type already ends with ?, use it as is, otherwise add ?
          final nullableType = type.endsWith('?') ? type : '$type?';
          return '    $nullableType ${f['name']},';
        })
        .join('\n');

    final copyWithMappings = fields
        .map((f) {
          return '      ${f['name']}: ${f['name']} ?? this.${f['name']},';
        })
        .join('\n');

    // Generate toJson method
    final toJsonMappings = fields
        .map((f) {
          return '      \'${f['name']}\': ${f['name']},';
        })
        .join('\n');

    // Generate fromJson factory - handle type casting properly
    final fromJsonMappings = fields
        .map((f) {
          final type = f['type'] as String;
          // For nullable types, handle null values
          if (f['isNullable']) {
            return '      ${f['name']}: json[\'${f['name']}\'] as $type,';
          } else {
            return '      ${f['name']}: json[\'${f['name']}\'] as $type,';
          }
        })
        .join('\n');

    // Generate equality comparisons
    final equalityComparisons = fields
        .map((f) {
          return '        other.${f['name']} == ${f['name']}';
        })
        .join(' &&\n');

    // Generate hashCode fields
    final hashCodeFields = fields
        .map((f) {
          return '      ${f['name']},';
        })
        .join('\n');

    // Generate toString fields
    final toStringFields = fields
        .map((f) {
          return '${f['name']}: \$${f['name']}';
        })
        .join(', ');

    return '''
// GENERATED CODE - DO NOT MODIFY BY HAND
// DTO for $entityClassName

part of '$entityFileName';

/// Data Transfer Object for $entityClassName
/// Excludes relationship fields and only includes primitive data
class $dtoClassName {
$fieldDeclarations

  const $dtoClassName({
$constructorParams
  });

  /// Create DTO from entity
  factory $dtoClassName.fromEntity($entityClassName entity) {
    return $dtoClassName(
$fromEntityMappings
    );
  }

  /// Convert DTO to entity
  $entityClassName toEntity() {
    return $entityClassName(
$toEntityMappings
    );
  }

  /// Create a copy with modified fields
  $dtoClassName copyWith({
$copyWithParams
  }) {
    return $dtoClassName(
$copyWithMappings
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
$toJsonMappings
    };
  }

  /// Create from JSON
  factory $dtoClassName.fromJson(Map<String, dynamic> json) {
    return $dtoClassName(
$fromJsonMappings
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is $dtoClassName &&
$equalityComparisons;
  }

  @override
  int get hashCode {
    return Object.hash(
$hashCodeFields
    );
  }

  @override
  String toString() {
    return '$dtoClassName($toStringFields)';
  }
}
''';
  }
}

Builder dtoGeneratorBuilder(BuilderOptions options) {
  return LibraryBuilder(
    DtoGenerator(),
    generatedExtension: '.dto.g.dart',
  );
}
