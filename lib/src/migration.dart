import 'package:dorm/src/database/database_connection.dart';
import 'package:dorm/src/schema.dart';

abstract class DatabaseMigration {
  late DatabaseConnection connection;
  late SchemaManager schemaManager;

  int get version;
  String get description;
  DatabaseType get dbType => DatabaseType.postgresql;

  void setConnection(DatabaseConnection conn) {
    connection = conn;
    schemaManager = SchemaManager(conn);
  }

  /// Migration up - create/modify schema
  Future<void> up();

  /// Migration down - rollback schema
  Future<void> down();

  /// Helper to create a table from schema (skips if exists)
  Future<void> createTable(DatabaseSchema schema) async {
    await schemaManager.createTable(schema);
  }

  /// Helper to drop a table (skips if not exists)
  Future<void> dropTable(String tableName) async {
    final sql = 'DROP TABLE IF EXISTS $tableName;';
    await connection.execute(sql);
  }

  /// Helper to check if table exists
  Future<bool> tableExists(String tableName) async {
    return await schemaManager.tableExists(tableName);
  }

  /// Helper to create index (skips if exists)
  Future<void> createIndex({
    required String name,
    required String table,
    required List<String> columns,
    bool unique = false,
  }) async {
    final exists = await schemaManager.indexExists(name, table);
    if (exists) return;

    final uniqueKeyword = unique ? 'UNIQUE ' : '';
    final sql =
        'CREATE ${uniqueKeyword}INDEX $name ON $table (${columns.join(', ')});';
    await connection.execute(sql);
  }

  /// Helper to drop index (skips if not exists)
  Future<void> dropIndex(String name) async {
    final sql = switch (dbType) {
      DatabaseType.mysql => 'DROP INDEX IF EXISTS $name;',
      _ => 'DROP INDEX IF EXISTS $name;',
    };
    await connection.execute(sql);
  }

  /// Helper to add column (skips if exists)
  Future<void> addColumn({
    required String table,
    required String column,
    required String type,
    bool nullable = true,
    String? defaultValue,
  }) async {
    final exists = await _columnExists(table, column);
    if (exists) return;

    final nullableStr = nullable ? '' : ' NOT NULL';
    final defaultStr = defaultValue != null ? ' DEFAULT $defaultValue' : '';
    final sql =
        'ALTER TABLE $table ADD COLUMN $column $type$nullableStr$defaultStr;';
    await connection.execute(sql);
  }

  /// Helper to drop column (skips if not exists)
  Future<void> dropColumn({
    required String table,
    required String column,
  }) async {
    final exists = await _columnExists(table, column);
    if (!exists) return;

    final sql = 'ALTER TABLE $table DROP COLUMN $column;';
    await connection.execute(sql);
  }

  Future<bool> _columnExists(String table, String column) async {
    final sql = switch (dbType) {
      DatabaseType.postgresql =>
        """
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = '$table' AND column_name = '$column'
      """,
      DatabaseType.mysql =>
        """
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = '$table' AND column_name = '$column'
      """,
      DatabaseType.sqlite =>
        """
        SELECT 1 FROM pragma_table_info('$table') WHERE name = '$column'
      """,
    };
    final result = await connection.query(sql);
    return result.isNotEmpty;
  }
}

// /// Example migration with PostgreSQL SERIAL support
// class Migration001CreateUsersTable extends DatabaseMigration {
//   @override
//   int get version => 1;

//   @override
//   String get description => 'Create users table with SERIAL primary key';

//   @override
//   Future<void> Up() async {
//     const sql = '''
//       CREATE TABLE IF NOT EXISTS users (
//         id SERIAL PRIMARY KEY,
//         email VARCHAR(100) NOT NULL UNIQUE,
//         name VARCHAR(100) NOT NULL,
//         bio VARCHAR(255),
//         status VARCHAR(50) NOT NULL DEFAULT 'ACTIVE',
//         created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
//         updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
//         CONSTRAINT email_check CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}$')
//       );
//
//       CREATE INDEX idx_users_email ON users(email);
//       CREATE INDEX idx_users_status ON users(status);
//     ''';

//     await connection.execute(sql);
//   }

//   @override
//   Future<void> Down() async {
//     const sql = 'DROP TABLE IF EXISTS users CASCADE;';
//     await connection.execute(sql);
//   }
// }

// class Migration002CreatePostsTable extends DatabaseMigration {
//   @override
//   int get version => 2;

//   @override
//   String get description => 'Create posts table with foreign keys';

//   @override
//   Future<void> Up() async {
//     const sql = '''
//       CREATE TABLE IF NOT EXISTS posts (
//         id SERIAL PRIMARY KEY,
//         title VARCHAR(255) NOT NULL,
//         content TEXT NOT NULL,
//         author_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
//         created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
//         CONSTRAINT title_length_check CHECK (LENGTH(title) >= 5)
//       );
//
//       CREATE INDEX idx_posts_author_id ON posts(author_id);
//       CREATE INDEX idx_posts_created_at ON posts(created_at);
//     ''';

//     await connection.execute(sql);
//   }

//   @override
//   Future<void> Down() async {
//     const sql = 'DROP TABLE IF EXISTS posts CASCADE;';
//     await connection.execute(sql);
//   }
// }

class MigrationRunner {
  final DatabaseConnection connection;
  final List<DatabaseMigration> migrations;

  MigrationRunner(this.connection, this.migrations);

  Future<void> runMigrations() async {
    // Create migrations tracking table
    await _ensureMigrationsTable();

    final applied = await _getAppliedMigrations();

    for (var migration in migrations) {
      if (!applied.contains(migration.version)) {
        migration.setConnection(connection);
        await migration.up();
        await _recordMigration(migration.version, migration.description);
        print('✓ Migration ${migration.version}: ${migration.description}');
      }
    }
  }

  Future<void> rollbackLast() async {
    final applied = await _getAppliedMigrations();
    if (applied.isEmpty) {
      print('No migrations to rollback');
      return;
    }

    final lastVersion = applied.last;
    final migration = migrations.firstWhere((m) => m.version == lastVersion);

    migration.setConnection(connection);
    await migration.down();
    await _removeMigrationRecord(lastVersion);
    print('✓ Rolled back migration $lastVersion');
  }

  Future<void> _ensureMigrationsTable() async {
    final sql = '''
      CREATE TABLE IF NOT EXISTS __migrations__ (
        version INTEGER PRIMARY KEY,
        description VARCHAR(255) NOT NULL,
        applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
    ''';
    await connection.execute(sql);
  }

  Future<List<int>> _getAppliedMigrations() async {
    final result = await connection.query(
      'SELECT version FROM __migrations__ ORDER BY version ASC',
    );
    return result.map((r) => r['version'] as int).toList();
  }

  Future<void> _recordMigration(int version, String description) async {
    final sql =
        'INSERT INTO __migrations__ (version, description) VALUES (@version, @description)';
    await connection.execute(
      sql,
      parameters: {'version': version, 'description': description},
    );
  }

  Future<void> _removeMigrationRecord(int version) async {
    final sql = 'DELETE FROM __migrations__ WHERE version = @version';
    await connection.execute(sql, parameters: {'version': version});
  }
}
