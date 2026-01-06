/// Represents metadata for a database column with type safety
class ColumnMetadata {
  /// The Dart field name (e.g., 'firstName')
  final String fieldName;

  /// The SQL column name (e.g., 'first_name')
  final String columnName;

  /// The Dart type as a string (e.g., 'String', 'int?')
  final String dartType;

  /// The SQL type (e.g., 'TEXT', 'INTEGER')
  final String sqlType;

  /// Whether this is a primary key
  final bool isPrimaryKey;

  /// Whether the column is nullable
  final bool isNullable;

  /// The table name this column belongs to
  final String tableName;

  const ColumnMetadata({
    required this.fieldName,
    required this.columnName,
    required this.dartType,
    required this.sqlType,
    required this.isPrimaryKey,
    required this.isNullable,
    required this.tableName,
  });

  /// Get the fully qualified column name (e.g., 'users.first_name')
  String get qualifiedName => '$tableName.$columnName';

  /// Get just the column name for SQL
  String toSql() => columnName;

  @override
  String toString() => columnName;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ColumnMetadata &&
        other.fieldName == fieldName &&
        other.columnName == columnName &&
        other.dartType == dartType &&
        other.sqlType == sqlType &&
        other.isPrimaryKey == isPrimaryKey &&
        other.isNullable == isNullable &&
        other.tableName == tableName;
  }

  @override
  int get hashCode {
    return Object.hash(
      fieldName,
      columnName,
      dartType,
      sqlType,
      isPrimaryKey,
      isNullable,
      tableName,
    );
  }
}
