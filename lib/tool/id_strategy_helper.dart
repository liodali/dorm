import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dormql/src/annotation.dart';
import 'package:dormql/src/database/database_connection.dart';

/// Helper utility for handling ID strategy validation and SQL generation
class IdStrategyHelper {
  /// Extract ID strategy from @Id annotation
  static IDStrategy? extractIdStrategy(ElementAnnotation? idAnnotation) {
    if (idAnnotation == null) return null;

    try {
      final source = idAnnotation.toSource();

      // Check for named constructors (postgres, mysql, sqlite, uuid)
      if (source.contains('Id.postgres')) return IDStrategy.serial;
      if (source.contains('Id.mysql')) return IDStrategy.autoIncrement;
      if (source.contains('Id.sqlite')) return IDStrategy.autoIncrementSqlite;
      if (source.contains('Id.uuid')) return IDStrategy.uuid;

      // Check for strategy parameter in default constructor
      final strategyMatch = RegExp(
        r'strategy\s*:\s*IDStrategy\.(\w+)',
      ).firstMatch(source);
      if (strategyMatch != null) {
        final strategyName = strategyMatch.group(1);
        return IDStrategy.values.firstWhere(
          (s) => s.name == strategyName,
          orElse: () => IDStrategy.autoIncrement,
        );
      }
    } catch (e) {
      // Silently fail and return null
    }

    return null;
  }

  /// Get SQL for ID strategy based on database type
  static String getIdStrategySQL(
    IDStrategy strategy,
    DatabaseType dbType,
  ) {
    switch (strategy) {
      case IDStrategy.serial:
        return strategy.label;
      case IDStrategy.autoIncrement:
        switch (dbType) {
          case DatabaseType.postgresql:
            return IDStrategy.serial.label;
          case DatabaseType.mysql:
            return IDStrategy.autoIncrement.label;
          case DatabaseType.sqlite:
            return IDStrategy.autoIncrementSqlite.label;
        }
      case IDStrategy.autoIncrementSqlite:
        return IDStrategy.autoIncrementSqlite.label;
      case IDStrategy.uuid:
        switch (dbType) {
          case DatabaseType.postgresql:
            return 'UUID DEFAULT gen_random_uuid()';
          case DatabaseType.mysql:
            return 'CHAR(36)';
          case DatabaseType.sqlite:
            return 'TEXT';
        }
    }
  }

  /// Get big version of ID strategy SQL
  static String getBigIdStrategySQL(
    IDStrategy strategy,
    DatabaseType dbType,
  ) {
    switch (strategy) {
      case IDStrategy.serial:
        return 'BIGSERIAL';
      case IDStrategy.autoIncrement:
        switch (dbType) {
          case DatabaseType.postgresql:
            return 'BIGSERIAL';
          case DatabaseType.mysql:
            return 'AUTO_INCREMENT';
          case DatabaseType.sqlite:
            return 'AUTOINCREMENT';
        }
      case IDStrategy.autoIncrementSqlite:
        return 'AUTOINCREMENT';
      case IDStrategy.uuid:
        switch (dbType) {
          case DatabaseType.postgresql:
            return 'UUID DEFAULT gen_random_uuid()';
          case DatabaseType.mysql:
            return 'CHAR(36)';
          case DatabaseType.sqlite:
            return 'TEXT';
        }
    }
  }

  /// Validate ID strategy against field type
  /// Returns error message if invalid, null if valid
  static String? validateIdStrategyForType(
    IDStrategy strategy,
    DartType fieldType,
  ) {
    final typeName = fieldType.getDisplayString().replaceAll('?', '');

    // UUID strategy only works with String
    if (strategy == IDStrategy.uuid) {
      if (typeName != 'String') {
        return 'UUID strategy can only be used with String type, but field is $typeName';
      }
      return null;
    }

    // AutoIncrement strategies only work with int or BigInt
    if (strategy == IDStrategy.serial ||
        strategy == IDStrategy.autoIncrement ||
        strategy == IDStrategy.autoIncrementSqlite) {
      if (typeName != 'int' && typeName != 'BigInt') {
        return 'AutoIncrement strategy (${strategy.label}) can only be used with int or BigInt type, but field is $typeName';
      }
      return null;
    }

    return null;
  }

  /// Check if strategy requires auto-increment behavior
  static bool isAutoIncrementStrategy(IDStrategy strategy) {
    return strategy != IDStrategy.uuid;
  }

  /// Check if strategy is UUID
  static bool isUuidStrategy(IDStrategy strategy) {
    return strategy == IDStrategy.uuid;
  }

  /// Get the strategy label for display
  static String getStrategyLabel(IDStrategy strategy) {
    return strategy.label;
  }

  /// Validate that @Id and @PrimaryKey are not used together on the same field
  /// Returns error message if invalid, null if valid
  static String? validateIdAndPrimaryKeyConflict(
    ElementAnnotation? idAnnotation,
    ElementAnnotation? columnAnnotation,
  ) {
    if (idAnnotation == null || columnAnnotation == null) {
      return null;
    }

    // Check if Column has primaryKey: true
    try {
      final source = columnAnnotation.toSource();
      if (source.contains('primaryKey') &&
          source.contains('primaryKey: true')) {
        return 'Cannot use both @Id and @Column(primaryKey: true) on the same field. '
            'Use @Id for single-field primary keys or @Column(primaryKey: true) for composite keys with @PrimaryKey.';
      }
    } catch (e) {
      // Silently fail
    }

    return null;
  }

  /// Validate ID field nullability
  /// ID fields must be nullable UNLESS autoIncrement is explicitly false AND strategy is not UUID
  /// Returns error message if invalid, null if valid
  static String? validateIdNullability(
    ElementAnnotation idAnnotation,
    bool isNullable,
  ) {
    try {
      final source = idAnnotation.toSource();

      // Extract autoIncrement value
      bool autoIncrement = true; // default
      final autoIncrementMatch = RegExp(
        r'autoIncrement\s*:\s*(true|false)',
      ).firstMatch(source);
      if (autoIncrementMatch != null) {
        autoIncrement = autoIncrementMatch.group(1) == 'true';
      }

      // Extract strategy
      final strategy = extractIdStrategy(idAnnotation);

      // ID field must be nullable UNLESS:
      // 1. autoIncrement is explicitly false AND
      // 2. strategy is not UUID
      if (!isNullable) {
        // Non-nullable ID is only allowed if autoIncrement is false and strategy is not UUID
        if (autoIncrement || strategy == IDStrategy.uuid) {
          return 'ID field must be nullable unless autoIncrement is explicitly set to false and strategy is not UUID. '
              'Use "int?" or "String?" instead of "int" or "String".';
        }
      }
    } catch (e) {
      // Silently fail and allow
    }

    return null;
  }
}
