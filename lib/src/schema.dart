/// Database schema representation for entities
class DatabaseSchema {
  final String tableName;
  final List<dynamic> columns;
  final List<ForeignKey>? foreignKeys;
  final List<IndexSchema>? indexes;

  const DatabaseSchema({
    required this.tableName,
    required this.columns,
    this.foreignKeys,
    this.indexes,
  });
}

/// Column schema definition
class ColumnSchema {
  final String name;
  final String type;
  final bool nullable;
  final bool primaryKey;
  final bool unique;
  final String? defaultValue;
  final bool autoIncrement;

  const ColumnSchema({
    required this.name,
    required this.type,
    this.nullable = true,
    this.primaryKey = false,
    this.unique = false,
    this.defaultValue,
    this.autoIncrement = false,
  });
}

/// Foreign key definition
class ForeignKey {
  final String column;
  final String referencedTable;
  final String referencedColumn;
  final ForeignKeyAction? onDelete;
  final ForeignKeyAction? onUpdate;

  const ForeignKey({
    required this.column,
    required this.referencedTable,
    required this.referencedColumn,
    this.onDelete,
    this.onUpdate,
  });
}

/// Index schema definition
class IndexSchema {
  final String name;
  final List<String> columns;
  final bool unique;

  const IndexSchema({
    required this.name,
    required this.columns,
    this.unique = false,
  });
}

/// Foreign key actions
enum ForeignKeyAction {
  cascade,
  restrict,
  setNull,
  setDefault,
  noAction,
}
