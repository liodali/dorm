import 'database/database_connection.dart';

/// Database schema representation for entities
class DatabaseSchema {
  final String tableName;
  final List<dynamic> columns;
  final List<ForeignKey>? foreignKeys;
  final List<IndexSchema>? indexes;
  final List<String>? primaryKeyColumns;
  final List<UniqueConstraint>? uniqueConstraints;
  final List<CheckConstraint>? checkConstraints;

  const DatabaseSchema({
    required this.tableName,
    required this.columns,
    this.foreignKeys,
    this.indexes,
    this.primaryKeyColumns,
    this.uniqueConstraints,
    this.checkConstraints,
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
  final String? name;

  const ForeignKey({
    required this.column,
    required this.referencedTable,
    required this.referencedColumn,
    this.onDelete,
    this.onUpdate,
    this.name,
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

/// Unique constraint definition
class UniqueConstraint {
  final List<String> columns;
  final String? name;

  const UniqueConstraint({required this.columns, this.name});
}

/// Check constraint definition
class CheckConstraint {
  final String expression;
  final String? name;

  const CheckConstraint({required this.expression, this.name});
}

/// Foreign key actions
enum ForeignKeyAction {
  cascade,
  restrict,
  setNull,
  setDefault,
  noAction,
}

// ============================================================================
// SQL Generation Extensions
// ============================================================================

/// Extension to convert DatabaseSchema to SQL
extension DatabaseSchemaToSql on DatabaseSchema {
  /// Generate CREATE TABLE SQL with IF NOT EXISTS
  String toCreateTableSql(DatabaseType dbType) {
    final buffer = StringBuffer();
    buffer.writeln('CREATE TABLE IF NOT EXISTS $tableName (');

    final columnDefs = <String>[];

    // Add column definitions
    for (final col in columns) {
      if (col is ColumnSchema) {
        columnDefs.add('  ${col.toSql(dbType)}');
      }
    }

    // Add composite primary key if specified
    if (primaryKeyColumns != null && primaryKeyColumns!.isNotEmpty) {
      columnDefs.add('  PRIMARY KEY (${primaryKeyColumns!.join(', ')})');
    }

    // Add unique constraints
    if (uniqueConstraints != null) {
      for (final uc in uniqueConstraints!) {
        final name = uc.name != null ? 'CONSTRAINT ${uc.name} ' : '';
        columnDefs.add('  ${name}UNIQUE (${uc.columns.join(', ')})');
      }
    }

    // Add check constraints
    if (checkConstraints != null) {
      for (final cc in checkConstraints!) {
        final name = cc.name != null ? 'CONSTRAINT ${cc.name} ' : '';
        columnDefs.add('  ${name}CHECK (${cc.expression})');
      }
    }

    // Add foreign keys
    if (foreignKeys != null) {
      for (final fk in foreignKeys!) {
        columnDefs.add('  ${fk.toSql(dbType)}');
      }
    }

    buffer.writeln(columnDefs.join(',\n'));
    buffer.write(')');

    // Add engine for MySQL
    if (dbType == DatabaseType.mysql) {
      buffer.write(' ENGINE=InnoDB');
    }

    buffer.write(';');
    return buffer.toString();
  }

  /// Generate CREATE INDEX SQL statements with IF NOT EXISTS
  List<String> toCreateIndexSql(DatabaseType dbType) {
    if (indexes == null || indexes!.isEmpty) return [];

    return indexes!.map((idx) {
      final uniqueKeyword = idx.unique ? 'UNIQUE ' : '';
      final ifNotExists = dbType == DatabaseType.sqlite ? '' : 'IF NOT EXISTS ';
      return 'CREATE ${uniqueKeyword}INDEX $ifNotExists${idx.name} ON $tableName (${idx.columns.join(', ')});';
    }).toList();
  }

  /// Generate DROP TABLE SQL
  String toDropTableSql(DatabaseType dbType) {
    return 'DROP TABLE IF EXISTS $tableName;';
  }

  /// Generate all SQL statements for this schema
  List<String> toAllSql(DatabaseType dbType) {
    return [
      toCreateTableSql(dbType),
      ...toCreateIndexSql(dbType),
    ];
  }
}

/// Extension to convert ColumnSchema to SQL
extension ColumnSchemaToSql on ColumnSchema {
  /// Generate column definition SQL
  String toSql(DatabaseType dbType) {
    final parts = <String>[name];

    // Type with auto-increment handling
    if (autoIncrement || primaryKey) {
      switch (dbType) {
        case DatabaseType.postgresql:
          parts.add(type == 'INTEGER' ? 'SERIAL' : 'BIGSERIAL');
        case DatabaseType.mysql:
          parts.add('$type AUTO_INCREMENT');
        case DatabaseType.sqlite:
          parts.add('INTEGER');
      }
    } else {
      parts.add(type);
    }

    // Primary key (for single column PK)
    if (primaryKey) {
      parts.add('PRIMARY KEY');
    }

    // Nullable
    if (!nullable && !primaryKey) {
      parts.add('NOT NULL');
    }

    // Unique
    if (unique && !primaryKey) {
      parts.add('UNIQUE');
    }

    // Default value
    if (defaultValue != null) {
      parts.add('DEFAULT $defaultValue');
    }

    return parts.join(' ');
  }
}

/// Extension to convert ForeignKey to SQL
extension ForeignKeyToSql on ForeignKey {
  /// Generate foreign key constraint SQL
  String toSql(DatabaseType dbType) {
    final buffer = StringBuffer();

    if (name != null) {
      buffer.write('CONSTRAINT $name ');
    }

    buffer.write('FOREIGN KEY ($column) ');
    buffer.write('REFERENCES $referencedTable ($referencedColumn)');

    if (onDelete != null) {
      buffer.write(' ON DELETE ${onDelete!.toSql()}');
    }

    if (onUpdate != null) {
      buffer.write(' ON UPDATE ${onUpdate!.toSql()}');
    }

    return buffer.toString();
  }
}

/// Extension to convert ForeignKeyAction to SQL
extension ForeignKeyActionToSql on ForeignKeyAction {
  String toSql() {
    switch (this) {
      case ForeignKeyAction.cascade:
        return 'CASCADE';
      case ForeignKeyAction.restrict:
        return 'RESTRICT';
      case ForeignKeyAction.setNull:
        return 'SET NULL';
      case ForeignKeyAction.setDefault:
        return 'SET DEFAULT';
      case ForeignKeyAction.noAction:
        return 'NO ACTION';
    }
  }
}

// ============================================================================
// Schema Manager for executing schema operations
// ============================================================================

/// Manager for creating and managing database schemas
class SchemaManager {
  final DatabaseConnection connection;

  SchemaManager(this.connection);

  /// Create a table if it doesn't exist
  Future<bool> createTable(DatabaseSchema schema) async {
    final sql = schema.toCreateTableSql(connection.databaseType);
    await connection.execute(sql);

    // Create indexes
    for (final indexSql in schema.toCreateIndexSql(connection.databaseType)) {
      await connection.execute(indexSql);
    }

    return true;
  }

  /// Create multiple tables
  Future<void> createTables(List<DatabaseSchema> schemas) async {
    for (final schema in schemas) {
      await createTable(schema);
    }
  }

  /// Drop a table if it exists
  Future<void> dropTable(DatabaseSchema schema) async {
    final sql = schema.toDropTableSql(connection.databaseType);
    await connection.execute(sql);
  }

  /// Check if a table exists
  Future<bool> tableExists(String tableName) async {
    final sql = _tableExistsQuery(tableName);
    final result = await connection.query(sql);
    return result.isNotEmpty;
  }

  String _tableExistsQuery(String tableName) {
    switch (connection.databaseType) {
      case DatabaseType.postgresql:
        return """
          SELECT 1 FROM information_schema.tables 
          WHERE table_schema = 'public' AND table_name = '$tableName'
        """;
      case DatabaseType.mysql:
        return """
          SELECT 1 FROM information_schema.tables 
          WHERE table_name = '$tableName'
        """;
      case DatabaseType.sqlite:
        return """
          SELECT 1 FROM sqlite_master 
          WHERE type = 'table' AND name = '$tableName'
        """;
    }
  }

  /// Check if an index exists
  Future<bool> indexExists(String indexName, String tableName) async {
    final sql = _indexExistsQuery(indexName, tableName);
    final result = await connection.query(sql);
    return result.isNotEmpty;
  }

  String _indexExistsQuery(String indexName, String tableName) {
    switch (connection.databaseType) {
      case DatabaseType.postgresql:
        return """
          SELECT 1 FROM pg_indexes 
          WHERE tablename = '$tableName' AND indexname = '$indexName'
        """;
      case DatabaseType.mysql:
        return """
          SELECT 1 FROM information_schema.statistics 
          WHERE table_name = '$tableName' AND index_name = '$indexName'
        """;
      case DatabaseType.sqlite:
        return """
          SELECT 1 FROM sqlite_master 
          WHERE type = 'index' AND name = '$indexName'
        """;
    }
  }

  /// Get all table names in the database
  Future<List<String>> getTableNames() async {
    final sql = _getTableNamesQuery();
    final result = await connection.query(sql);
    return result.map((r) => r.values.first.toString()).toList();
  }

  String _getTableNamesQuery() {
    switch (connection.databaseType) {
      case DatabaseType.postgresql:
        return """
          SELECT table_name FROM information_schema.tables 
          WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
        """;
      case DatabaseType.mysql:
        return """
          SELECT table_name FROM information_schema.tables 
          WHERE table_schema = DATABASE()
        """;
      case DatabaseType.sqlite:
        return """
          SELECT name FROM sqlite_master 
          WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
        """;
    }
  }
}
