import 'package:test/test.dart';
import 'package:dormql/src/schema.dart';
import 'package:dormql/src/database/database_connection.dart';

class MockDatabaseConnection implements DatabaseConnection {
  final List<Map<String, dynamic>> mockResults;
  final List<String> executedStatements = [];
  Map<String, dynamic>? lastParameters;

  MockDatabaseConnection({this.mockResults = const []});

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    executedStatements.add(sql);
    lastParameters = parameters;
    return mockResults;
  }

  @override
  Future<int> execute(String sql, {Map<String, dynamic>? parameters}) async {
    executedStatements.add(sql);
    lastParameters = parameters;
    return 1;
  }

  @override
  Future<List<List<dynamic>>> rawQuery(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    return [];
  }

  @override
  Future<DatabaseTransaction> beginTransaction() async {
    throw UnimplementedError();
  }

  @override
  Future<void> close() async {}

  @override
  bool get isOpen => true;

  @override
  DatabaseType get databaseType => DatabaseType.postgresql;
}

void main() {
  group('SchemaManager', () {
    late MockDatabaseConnection connection;
    late SchemaManager schemaManager;

    setUp(() {
      connection = MockDatabaseConnection();
      schemaManager = SchemaManager(connection);
    });

    group('createTable', () {
      test('creates table with simple schema', () async {
        const schema = DatabaseSchema(
          tableName: 'users',
          columns: [
            ColumnSchema(name: 'id', type: 'INTEGER', primaryKey: true),
            ColumnSchema(name: 'name', type: 'TEXT'),
          ],
        );

        final result = await schemaManager.createTable(schema);

        expect(result, true);
        expect(connection.executedStatements.length, 1);
        expect(
          connection.executedStatements[0],
          contains('CREATE TABLE IF NOT EXISTS users'),
        );
      });

      test('creates table with indexes', () async {
        const schema = DatabaseSchema(
          tableName: 'users',
          columns: [
            ColumnSchema(name: 'id', type: 'INTEGER', primaryKey: true),
            ColumnSchema(name: 'email', type: 'VARCHAR'),
          ],
          indexes: [
            IndexSchema(name: 'idx_users_email', columns: ['email']),
          ],
        );

        await schemaManager.createTable(schema);

        expect(connection.executedStatements.length, 2);
        expect(connection.executedStatements[0], contains('CREATE TABLE'));
        expect(connection.executedStatements[1], contains('CREATE INDEX'));
      });

      test('creates table with multiple indexes', () async {
        const schema = DatabaseSchema(
          tableName: 'users',
          columns: [
            ColumnSchema(name: 'id', type: 'INTEGER', primaryKey: true),
            ColumnSchema(name: 'email', type: 'VARCHAR'),
            ColumnSchema(name: 'name', type: 'TEXT'),
          ],
          indexes: [
            IndexSchema(name: 'idx_users_email', columns: ['email']),
            IndexSchema(name: 'idx_users_name', columns: ['name']),
          ],
        );

        await schemaManager.createTable(schema);

        expect(connection.executedStatements.length, 3);
      });
    });

    group('createTables', () {
      test('creates multiple tables', () async {
        const schemas = [
          DatabaseSchema(
            tableName: 'users',
            columns: [
              ColumnSchema(name: 'id', type: 'INTEGER', primaryKey: true),
            ],
          ),
          DatabaseSchema(
            tableName: 'posts',
            columns: [
              ColumnSchema(name: 'id', type: 'INTEGER', primaryKey: true),
            ],
          ),
        ];

        await schemaManager.createTables(schemas);

        expect(connection.executedStatements.length, 2);
        expect(connection.executedStatements[0], contains('users'));
        expect(connection.executedStatements[1], contains('posts'));
      });
    });

    group('dropTable', () {
      test('drops table', () async {
        const schema = DatabaseSchema(
          tableName: 'users',
          columns: [
            ColumnSchema(name: 'id', type: 'INTEGER', primaryKey: true),
          ],
        );

        await schemaManager.dropTable(schema);

        expect(connection.executedStatements.length, 1);
        expect(connection.executedStatements[0], 'DROP TABLE IF EXISTS users;');
      });
    });

    group('tableExists', () {
      test('returns true when table exists (PostgreSQL)', () async {
        connection = MockDatabaseConnection(
          mockResults: [
            {'exists': 1},
          ],
        );
        schemaManager = SchemaManager(connection);

        final exists = await schemaManager.tableExists('users');

        expect(exists, true);
        expect(
          connection.executedStatements[0],
          contains('information_schema.tables'),
        );
        expect(
          connection.executedStatements[0],
          contains("table_name = 'users'"),
        );
      });

      test('returns false when table does not exist', () async {
        connection = MockDatabaseConnection(mockResults: []);
        schemaManager = SchemaManager(connection);

        final exists = await schemaManager.tableExists('nonexistent');

        expect(exists, false);
      });

      test('uses correct query for MySQL', () async {
        connection = MockDatabaseConnection(mockResults: []);
        connection = _MockMySQLConnection(mockResults: []);
        schemaManager = SchemaManager(connection);

        await schemaManager.tableExists('users');

        expect(
          connection.executedStatements[0],
          contains('information_schema.tables'),
        );
      });

      test('uses correct query for SQLite', () async {
        connection = _MockSQLiteConnection(mockResults: []);
        schemaManager = SchemaManager(connection);

        await schemaManager.tableExists('users');

        expect(connection.executedStatements[0], contains('sqlite_master'));
      });
    });

    group('indexExists', () {
      test('returns true when index exists (PostgreSQL)', () async {
        connection = MockDatabaseConnection(
          mockResults: [
            {'exists': 1},
          ],
        );
        schemaManager = SchemaManager(connection);

        final exists = await schemaManager.indexExists(
          'idx_users_email',
          'users',
        );

        expect(exists, true);
        expect(connection.executedStatements[0], contains('pg_indexes'));
      });

      test('returns false when index does not exist', () async {
        connection = MockDatabaseConnection(mockResults: []);
        schemaManager = SchemaManager(connection);

        final exists = await schemaManager.indexExists('nonexistent', 'users');

        expect(exists, false);
      });

      test('uses correct query for MySQL', () async {
        connection = _MockMySQLConnection(mockResults: []);
        schemaManager = SchemaManager(connection);

        await schemaManager.indexExists('idx_users_email', 'users');

        expect(
          connection.executedStatements[0],
          contains('information_schema.statistics'),
        );
      });

      test('uses correct query for SQLite', () async {
        connection = _MockSQLiteConnection(mockResults: []);
        schemaManager = SchemaManager(connection);

        await schemaManager.indexExists('idx_users_email', 'users');

        expect(connection.executedStatements[0], contains('sqlite_master'));
      });
    });

    group('getTableNames', () {
      test('returns list of table names (PostgreSQL)', () async {
        connection = MockDatabaseConnection(
          mockResults: [
            {'table_name': 'users'},
            {'table_name': 'posts'},
            {'table_name': 'comments'},
          ],
        );
        schemaManager = SchemaManager(connection);

        final tables = await schemaManager.getTableNames();

        expect(tables, ['users', 'posts', 'comments']);
        expect(
          connection.executedStatements[0],
          contains('information_schema.tables'),
        );
        expect(
          connection.executedStatements[0],
          contains("table_schema = 'public'"),
        );
      });

      test('returns empty list when no tables', () async {
        connection = MockDatabaseConnection(mockResults: []);
        schemaManager = SchemaManager(connection);

        final tables = await schemaManager.getTableNames();

        expect(tables, isEmpty);
      });

      test('uses correct query for MySQL', () async {
        connection = _MockMySQLConnection(mockResults: []);
        schemaManager = SchemaManager(connection);

        await schemaManager.getTableNames();

        expect(connection.executedStatements[0], contains('DATABASE()'));
      });

      test('uses correct query for SQLite', () async {
        connection = _MockSQLiteConnection(mockResults: []);
        schemaManager = SchemaManager(connection);

        await schemaManager.getTableNames();

        expect(connection.executedStatements[0], contains('sqlite_master'));
        expect(connection.executedStatements[0], contains("type = 'table'"));
      });
    });
  });
}

class _MockMySQLConnection extends MockDatabaseConnection {
  _MockMySQLConnection({super.mockResults});

  @override
  DatabaseType get databaseType => DatabaseType.mysql;
}

class _MockSQLiteConnection extends MockDatabaseConnection {
  _MockSQLiteConnection({super.mockResults});

  @override
  DatabaseType get databaseType => DatabaseType.sqlite;
}
