import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/source/source_range.dart';

import '../visitor/entity_visitor.dart';
import '../utils/annotation_checker.dart';
import 'rule.dart';

/// Rules for validating @Entity classes and their fields.
final class EntityRules implements Rule {
  @override
  String get ruleId => 'dormql_entity_rules';

  @override
  String get description =>
      'Validates @Entity classes, @Id annotations, and type compatibility';

  @override
  List<Diagnostic> analyze(ResolvedUnitResult unit) {
    final diagnostics = <Diagnostic>[];
    final visitor = EntityVisitor();

    unit.unit.accept(visitor);

    for (final entity in visitor.entities) {
      diagnostics.addAll(_validateEntity(entity));
    }

    return diagnostics;
  }

  List<Diagnostic> _validateEntity(EntityInfo entity) {
    final diagnostics = <Diagnostic>[];

    // Rule 1: Check for @Id and @PrimaryKey conflict
    diagnostics.addAll(_checkIdPrimaryKeyConflict(entity));

    // Rule 2: Check for missing primary key
    diagnostics.addAll(_checkMissingPrimaryKey(entity));

    // Rule 3: Check for multiple @Id annotations
    diagnostics.addAll(_checkMultipleIds(entity));

    // Rule 4: Validate @Id type compatibility
    diagnostics.addAll(_checkIdTypeCompatibility(entity));

    // Rule 5: Check @Column(primaryKey: true) conflicts
    diagnostics.addAll(_checkColumnPrimaryKeyConflict(entity));

    // Rule 6: Validate @PrimaryKey columns exist
    diagnostics.addAll(_checkPrimaryKeyColumnsExist(entity));

    // Rule 7: Validate @Column type compatibility
    diagnostics.addAll(_checkColumnTypeCompatibility(entity));

    return diagnostics;
  }

  /// Rule 1: Cannot use both @Id and @PrimaryKey in the same entity.
  List<Diagnostic> _checkIdPrimaryKeyConflict(EntityInfo entity) {
    if (entity.idFields.isNotEmpty && entity.hasPrimaryKeyAnnotation) {
      return [
        Diagnostic(
          code: DormQLErrorCodes.idAndPrimaryKeyConflict,
          message:
              'Cannot use both @Id and @PrimaryKey in the same entity "${entity.className}". '
              'Use @Id for single-field primary keys or @PrimaryKey for composite keys.',
          severity: DiagnosticSeverity.error,
          range: SourceRange(
            entity.classNode.name.offset,
            entity.classNode.name.length,
          ),
        ),
      ];
    }
    return [];
  }

  /// Rule 2: Entity must have either @Id or @PrimaryKey.
  List<Diagnostic> _checkMissingPrimaryKey(EntityInfo entity) {
    if (entity.idFields.isEmpty && !entity.hasPrimaryKeyAnnotation) {
      return [
        Diagnostic(
          code: DormQLErrorCodes.missingId,
          message:
              'Entity "${entity.className}" must have a primary key. '
              'Add @Id to a field or @PrimaryKey to the class for composite keys.',
          severity: DiagnosticSeverity.error,
          range: SourceRange(
            entity.classNode.name.offset,
            entity.classNode.name.length,
          ),
        ),
      ];
    }
    return [];
  }

  /// Rule 3: Only one @Id annotation per entity.
  List<Diagnostic> _checkMultipleIds(EntityInfo entity) {
    if (entity.idFields.length > 1) {
      final diagnostics = <Diagnostic>[];
      for (var i = 1; i < entity.idFields.length; i++) {
        final idField = entity.idFields[i];
        diagnostics.add(
          Diagnostic(
            code: DormQLErrorCodes.multipleIds,
            message:
                'Entity "${entity.className}" has multiple @Id annotations. '
                'Use only one @Id, or use @PrimaryKey for composite keys.',
            severity: DiagnosticSeverity.error,
            range: SourceRange(
              idField.annotation.offset,
              idField.annotation.length,
            ),
          ),
        );
      }
      return diagnostics;
    }
    return [];
  }

  /// Rule 4: Validate @Id type compatibility with strategy.
  List<Diagnostic> _checkIdTypeCompatibility(EntityInfo entity) {
    final diagnostics = <Diagnostic>[];

    for (final idField in entity.idFields) {
      final strategy = idField.strategy;
      final typeName = idField.typeName;

      if (typeName == null) continue;

      // UUID strategy requires String type
      if (_isUuidStrategy(strategy)) {
        if (typeName != 'String') {
          diagnostics.add(
            Diagnostic(
              code: DormQLErrorCodes.uuidRequiresString,
              message:
                  'UUID strategy requires String type, but field is "$typeName". '
                  'Change the field type to String or use a different ID strategy.',
              severity: DiagnosticSeverity.error,
              range: SourceRange(idField.field.offset, idField.field.length),
            ),
          );
        }
      }
      // AutoIncrement/Serial strategies require int or BigInt
      else if (_isAutoIncrementStrategy(strategy)) {
        if (!_isIntegerType(typeName)) {
          diagnostics.add(
            Diagnostic(
              code: DormQLErrorCodes.autoIncrementRequiresInt,
              message:
                  'AutoIncrement/Serial strategy requires int or BigInt type, '
                  'but field is "$typeName". Change the field type or use UUID strategy.',
              severity: DiagnosticSeverity.error,
              range: SourceRange(idField.field.offset, idField.field.length),
            ),
          );
        }
      }
    }

    return diagnostics;
  }

  /// Rule 5: Check for @Column(primaryKey: true) conflicts with @Id.
  List<Diagnostic> _checkColumnPrimaryKeyConflict(EntityInfo entity) {
    final diagnostics = <Diagnostic>[];

    for (final field in entity.fields) {
      final hasColumnPK = AnnotationChecker.hasColumnPrimaryKey(field);
      final hasId = AnnotationChecker.getIdAnnotation(field) != null;

      if (hasColumnPK && hasId) {
        diagnostics.add(
          Diagnostic(
            code: DormQLErrorCodes.idAndPrimaryKeyConflict,
            message:
                'Cannot use both @Id and @Column(primaryKey: true) on the same field. '
                'Use @Id alone for primary key fields.',
            severity: DiagnosticSeverity.error,
            range: SourceRange(field.offset, field.length),
          ),
        );
      }
    }

    return diagnostics;
  }

  /// Rule 6: Validate that @PrimaryKey columns exist as fields.
  List<Diagnostic> _checkPrimaryKeyColumnsExist(EntityInfo entity) {
    if (!entity.hasPrimaryKeyAnnotation || entity.primaryKeyColumns == null) {
      return [];
    }

    final diagnostics = <Diagnostic>[];
    final fieldNames = entity.fields
        .expand((f) => f.fields.variables.map((v) => v.name.lexeme))
        .toSet();

    for (final column in entity.primaryKeyColumns!) {
      // Convert snake_case column to camelCase field name for comparison
      final camelCaseColumn = _snakeToCamel(column);

      if (!fieldNames.contains(column) &&
          !fieldNames.contains(camelCaseColumn)) {
        diagnostics.add(
          Diagnostic(
            code: DormQLErrorCodes.invalidPrimaryKeyColumn,
            message:
                '@PrimaryKey column "$column" does not exist as a field in "${entity.className}".',
            severity: DiagnosticSeverity.error,
            range: SourceRange(
              entity.classNode.name.offset,
              entity.classNode.name.length,
            ),
          ),
        );
      }
    }

    return diagnostics;
  }

  /// Rule 7: Validate @Column type compatibility with Dart type.
  List<Diagnostic> _checkColumnTypeCompatibility(EntityInfo entity) {
    final diagnostics = <Diagnostic>[];

    for (final columnField in entity.columnFields) {
      final columnType = columnField.columnType;
      final dartType = columnField.dartType;

      // Skip if no explicit columnType specified (default is text)
      if (columnType == null || dartType == null) continue;

      final compatibleTypes = _getCompatibleDartTypes(columnType);
      if (compatibleTypes.isNotEmpty && !compatibleTypes.contains(dartType)) {
        diagnostics.add(
          Diagnostic(
            code: DormQLErrorCodes.columnTypeMismatch,
            message:
                'ColumnType.$columnType is incompatible with Dart type "$dartType". '
                'Expected one of: ${compatibleTypes.join(", ")}.',
            severity: DiagnosticSeverity.error,
            range: SourceRange(
              columnField.field.offset,
              columnField.field.length,
            ),
            correctionMessage:
                'Change the Dart type to one of: ${compatibleTypes.join(", ")}',
          ),
        );
      }
    }

    return diagnostics;
  }

  /// Returns the list of compatible Dart types for a given ColumnType.
  List<String> _getCompatibleDartTypes(String columnType) {
    return switch (columnType) {
      'integer' || 'serial' || 'bigserial' => ['int', 'BigInt'],
      'text' || 'uuid' => ['String'],
      'boolean' => ['bool'],
      'real' => ['double', 'num'],
      'timestamp' => ['DateTime'],
      'json' => ['String', 'Map', 'List'],
      _ => [], // Unknown type, no validation
    };
  }

  bool _isUuidStrategy(String? strategy) {
    return strategy == 'uuid';
  }

  bool _isAutoIncrementStrategy(String? strategy) {
    // null means default, which is autoIncrement
    return strategy == null ||
        strategy == 'serial' ||
        strategy == 'autoIncrement' ||
        strategy == 'autoIncrementSqlite' ||
        strategy == 'postgres' ||
        strategy == 'mysql' ||
        strategy == 'sqlite';
  }

  bool _isIntegerType(String typeName) {
    return typeName == 'int' || typeName == 'BigInt';
  }

  String _snakeToCamel(String snake) {
    final parts = snake.split('_');
    if (parts.isEmpty) return snake;

    return parts.first +
        parts
            .skip(1)
            .map((p) => p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1))
            .join();
  }
}
