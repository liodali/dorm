import 'package:analyzer/dart/element/element.dart';
import 'package:dormql/src/database/database_connection.dart';
import 'package:source_gen/source_gen.dart';

/// Helper utility for extracting database type from @Db annotation
class DbTypeHelper {
  /// Extract DatabaseType from @Db annotation in a specific class element
  ///
  /// Searches the class and its library for a @Db annotation and extracts the dbType
  /// from its DbConfig. Returns the database type or defaults to PostgreSQL.
  static DatabaseType extractDbTypeFromElement(ClassElement element) {
    try {
      // First check if the element itself has @Db annotation
      final dbAnnotation = _getDbAnnotation(element);
      if (dbAnnotation != null) {
        return _extractDbTypeFromConfig(dbAnnotation);
      }

      // Then search through the library for @Db annotation
      final library = element.library;
      for (final libElement in library.classes) {
        final libDbAnnotation = _getDbAnnotation(libElement);
        if (libDbAnnotation != null) {
          return _extractDbTypeFromConfig(libDbAnnotation);
        }
      }
    } catch (e) {
      // If extraction fails, return default
    }

    // Default to PostgreSQL if no @Db annotation found
    return DatabaseType.postgresql;
  }

  /// Extract DatabaseType from a specific @Db annotation
  static DatabaseType extractDbType(ConstantReader annotation) {
    try {
      return _extractDbTypeFromConfig(annotation);
    } catch (e) {
      return DatabaseType.postgresql;
    }
  }

  /// Get the database type string (postgresql, mysql, sqlite)
  static String getDbTypeString(DatabaseType dbType) {
    switch (dbType) {
      case DatabaseType.postgresql:
        return 'postgresql';
      case DatabaseType.mysql:
        return 'mysql';
      case DatabaseType.sqlite:
        return 'sqlite';
    }
  }

  /// Get the autoIncrement SQL syntax for the given database type
  static String getAutoIncrementSql(DatabaseType dbType) {
    switch (dbType) {
      case DatabaseType.postgresql:
        return 'SERIAL';
      case DatabaseType.mysql:
        return 'AUTO_INCREMENT';
      case DatabaseType.sqlite:
        return 'AUTOINCREMENT';
    }
  }

  /// Get the bigserial/big autoIncrement SQL syntax for the given database type
  static String getBigAutoIncrementSql(DatabaseType dbType) {
    switch (dbType) {
      case DatabaseType.postgresql:
        return 'BIGSERIAL';
      case DatabaseType.mysql:
        return 'AUTO_INCREMENT';
      case DatabaseType.sqlite:
        return 'AUTOINCREMENT';
    }
  }

  /// Private helper to extract dbType from DbConfig in @Db annotation
  static DatabaseType _extractDbTypeFromConfig(ConstantReader annotation) {
    final configReader = annotation.peek('config');
    if (configReader == null || configReader.isNull) {
      return DatabaseType.postgresql;
    }

    final configObj = configReader.objectValue;
    final dbTypeField = configObj.getField('dbType');

    if (dbTypeField != null) {
      final index = dbTypeField.getField('index')?.toIntValue();
      if (index != null && index < DatabaseType.values.length) {
        return DatabaseType.values[index];
      }
    }

    return DatabaseType.postgresql;
  }

  /// Private helper to get @Db annotation from a class element
  static ConstantReader? _getDbAnnotation(ClassElement element) {
    try {
      for (final annotation in element.metadata.annotations) {
        if (annotation.element?.enclosingElement?.name == 'Db') {
          final value = annotation.computeConstantValue();
          if (value != null) {
            return ConstantReader(value);
          }
        }
      }
    } catch (e) {
      // Silently fail if annotation processing fails
    }
    return null;
  }
}
