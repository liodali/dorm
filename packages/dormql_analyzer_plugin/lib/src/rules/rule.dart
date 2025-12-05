import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/source/source_range.dart';

/// Severity levels for diagnostics.
enum DiagnosticSeverity { error, warning, info, hint }

/// Represents a diagnostic issue found during analysis.
final class Diagnostic {
  final String code;
  final String message;
  final DiagnosticSeverity severity;
  final SourceRange range;
  final String? correctionMessage;

  const Diagnostic({
    required this.code,
    required this.message,
    required this.severity,
    required this.range,
    this.correctionMessage,
  });
}

/// Error codes for DormQL diagnostics.
abstract final class DormQLErrorCodes {
  // Entity Rules (1xx)
  static const String missingId = 'dormql_missing_id';
  static const String multipleIds = 'dormql_multiple_ids';
  static const String idAndPrimaryKeyConflict = 'dormql_id_primarykey_conflict';
  static const String idTypeMismatch = 'dormql_id_type_mismatch';
  static const String uuidRequiresString = 'dormql_uuid_requires_string';
  static const String autoIncrementRequiresInt =
      'dormql_autoincrement_requires_int';
  static const String columnTypeMismatch = 'dormql_column_type_mismatch';
  static const String invalidPrimaryKeyColumn =
      'dormql_invalid_primarykey_column';

  // Relationship Rules (2xx)
  static const String invalidTargetEntity = 'dormql_invalid_target_entity';
  static const String invalidMappedBy = 'dormql_invalid_mapped_by';
  static const String missingOwningSide = 'dormql_missing_owning_side';
  static const String missingJoinTable = 'dormql_missing_join_table';
  static const String relationshipTypeMismatch =
      'dormql_relationship_type_mismatch';

  // Database Rules (3xx)
  static const String invalidEntityInDb = 'dormql_invalid_entity_in_db';
  static const String schemaChangedNoVersionBump =
      'dormql_schema_changed_no_version_bump';
  static const String invalidMigrationVersion =
      'dormql_invalid_migration_version';
}

/// Base interface for all DormQL analysis rules.
abstract interface class Rule {
  /// Unique identifier for this rule.
  String get ruleId;

  /// Human-readable description of what this rule checks.
  String get description;

  /// Analyzes the given resolved unit and returns diagnostics.
  List<Diagnostic> analyze(ResolvedUnitResult unit);
}
