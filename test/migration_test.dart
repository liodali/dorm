import 'package:test/test.dart';
import 'package:dormql/src/migration.dart';
import 'package:dormql/src/schema.dart';
import 'package:dormql/src/database/database_connection.dart';

class MockDatabaseConnection implements DatabaseConnection {
  final List<Map<String, dynamic>> mockResults;
  final List<String> executedStatements = [];
  final List<Map<String, dynamic>> executedParameters = [];

  MockDatabaseConnection({this.mockResults = const []});

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    executedStatements.add(sql);
    if (parameters != null) {
      executedParameters.add(parameters);
    }
    return mockResults;
  }

  @override
  Future<int> execute(String sql, {Map<String, dynamic>? parameters}) async {
    executedStatements.add(sql);
    if (parameters != null) {
      executedParameters.add(parameters);
    }
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

class TestMigration extends DatabaseMigration {
  final int _version;
  final String _description;
  bool upCalled = false;
  bool downCalled = false;

  TestMigration(this._version, this._description);

  @override
  int get version => _version;

  @override
  String get description => _description;

  @override
  Future<void> up() async {
    upCalled = true;
  }

  @override
  Future<void> down() async {
    downCalled = true;
  }
}

void main() {
  group('DatabaseMigration', () {
    late MockDatabaseConnection connection;
    late TestMigration migration;

    setUp(() {
      connection = MockDatabaseConnection();
      migration = TestMigration(1, 'Test migration');
      migration.setConnection(connection);
    });

    test('has version and description', () {
      expect(migration.version, 1);
      expect(migration.description, 'Test migration');
    });

    test('setConnection sets connection and schema manager', () {
      expect(migration.connection, connection);
      expect(migration.schemaManager, isNotNull);
    });

    test('dbType defaults to PostgreSQL', () {
      expect(migration.dbType, DatabaseType.postgresql);
    });

    group('Helper Methods', () {
      test('createTable creates table using schema manager', () async {
        const schema = DatabaseSchema(
          tableName: 'users',
          columns: [
            ColumnSchema(name: 'id', type: 'INTEGER', primaryKey: true),
          ],
        );

        await migration.createTable(schema);

        expect(connection.executedStatements.length, 1);
        expect(connection.executedStatements[0], contains('CREATE TABLE'));
      });

      test('dropTable drops table', () async {
        await migration.dropTable('users');

        expect(connection.executedStatements.length, 1);
        expect(connection.executedStatements[0], 'DROP TABLE IF EXISTS users;');
      });

      test('tableExists checks if table exists', () async {
        connection = MockDatabaseConnection(
          mockResults: [
            {'exists': 1},
          ],
        );
        migration.setConnection(connection);

        final exists = await migration.tableExists('users');

        expect(exists, true);
      });

      test('createIndex creates index', () async {
        connection = MockDatabaseConnection(mockResults: []);
        migration.setConnection(connection);

        await migration.createIndex(
          name: 'idx_users_email',
          table: 'users',
          columns: ['email'],
        );

        expect(
          connection.executedStatements.any((s) => s.contains('CREATE INDEX')),
          true,
        );
      });

      test('createIndex with unique flag', () async {
        connection = MockDatabaseConnection(mockResults: []);
        migration.setConnection(connection);

        await migration.createIndex(
          name: 'idx_users_email',
          table: 'users',
          columns: ['email'],
          unique: true,
        );

        expect(
          connection.executedStatements.any(
            (s) => s.contains('CREATE UNIQUE INDEX'),
          ),
          true,
        );
      });

      test('dropIndex drops index', () async {
        await migration.dropIndex('idx_users_email');

        expect(connection.executedStatements.length, 1);
        expect(connection.executedStatements[0], contains('DROP INDEX'));
      });

      test('addColumn adds column', () async {
        connection = MockDatabaseConnection(mockResults: []);
        migration.setConnection(connection);

        await migration.addColumn(
          table: 'users',
          column: 'age',
          type: 'INTEGER',
        );

        expect(
          connection.executedStatements.any((s) => s.contains('ALTER TABLE')),
          true,
        );
        expect(
          connection.executedStatements.any((s) => s.contains('ADD COLUMN')),
          true,
        );
      });

      test('addColumn with NOT NULL requires default value', () async {
        expect(
          () => migration.addColumn(
            table: 'users',
            column: 'age',
            type: 'INTEGER',
            nullable: false,
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('addColumn with NOT NULL and default value succeeds', () async {
        connection = MockDatabaseConnection(mockResults: []);
        migration.setConnection(connection);

        await migration.addColumn(
          table: 'users',
          column: 'age',
          type: 'INTEGER',
          nullable: false,
          defaultValue: '0',
        );

        expect(
          connection.executedStatements.any((s) => s.contains('NOT NULL')),
          true,
        );
        expect(
          connection.executedStatements.any((s) => s.contains('DEFAULT')),
          true,
        );
      });

      test('dropColumn drops column', () async {
        connection = MockDatabaseConnection(
          mockResults: [
            {'exists': 1},
          ],
        );
        migration.setConnection(connection);

        await migration.dropColumn(table: 'users', column: 'age');

        expect(
          connection.executedStatements.any((s) => s.contains('DROP COLUMN')),
          true,
        );
      });
    });
  });

  group('RawSqlMigration', () {
    late MockDatabaseConnection connection;

    setUp(() {
      connection = MockDatabaseConnection();
    });

    test('creates migration with single SQL statement', () {
      final migration = RawSqlMigration(
        version: 1,
        description: 'Add status column',
        upSql:
            "ALTER TABLE users ADD COLUMN status VARCHAR(50) DEFAULT 'active';",
        downSql: 'ALTER TABLE users DROP COLUMN status;',
      );

      expect(migration.version, 1);
      expect(migration.description, 'Add status column');
    });

    test('executes up SQL', () async {
      final migration = RawSqlMigration(
        version: 1,
        description: 'Test migration',
        upSql: 'CREATE TABLE test (id INTEGER);',
      );
      migration.setConnection(connection);

      await migration.up();

      expect(connection.executedStatements.length, 1);
      expect(
        connection.executedStatements[0],
        'CREATE TABLE test (id INTEGER);',
      );
    });

    test('executes down SQL', () async {
      final migration = RawSqlMigration(
        version: 1,
        description: 'Test migration',
        upSql: 'CREATE TABLE test (id INTEGER);',
        downSql: 'DROP TABLE test;',
      );
      migration.setConnection(connection);

      await migration.down();

      expect(connection.executedStatements.length, 1);
      expect(connection.executedStatements[0], 'DROP TABLE test;');
    });

    test('executes multiple up SQL statements', () async {
      final migration = RawSqlMigration(
        version: 1,
        description: 'Test migration',
        upSqlStatements: [
          'CREATE TABLE users (id INTEGER);',
          'CREATE TABLE posts (id INTEGER);',
        ],
      );
      migration.setConnection(connection);

      await migration.up();

      expect(connection.executedStatements.length, 2);
      expect(connection.executedStatements[0], contains('users'));
      expect(connection.executedStatements[1], contains('posts'));
    });

    test('executes multiple down SQL statements', () async {
      final migration = RawSqlMigration(
        version: 1,
        description: 'Test migration',
        downSqlStatements: [
          'DROP TABLE posts;',
          'DROP TABLE users;',
        ],
      );
      migration.setConnection(connection);

      await migration.down();

      expect(connection.executedStatements.length, 2);
    });

    test('down does nothing when no downSql provided', () async {
      final migration = RawSqlMigration(
        version: 1,
        description: 'Test migration',
        upSql: 'CREATE TABLE test (id INTEGER);',
      );
      migration.setConnection(connection);

      await migration.down();

      expect(connection.executedStatements, isEmpty);
    });
  });

  group('ManualMigration', () {
    late MockDatabaseConnection connection;

    setUp(() {
      connection = MockDatabaseConnection();
    });

    test('creates migration with callbacks', () {
      final migration = ManualMigration(
        version: 1,
        description: 'Seed data',
        onUp: (conn, schema) async {},
      );

      expect(migration.version, 1);
      expect(migration.description, 'Seed data');
    });

    test('executes onUp callback', () async {
      var upCalled = false;
      final migration = ManualMigration(
        version: 1,
        description: 'Test migration',
        onUp: (conn, schema) async {
          upCalled = true;
        },
      );
      migration.setConnection(connection);

      await migration.up();

      expect(upCalled, true);
    });

    test('executes onDown callback', () async {
      var downCalled = false;
      final migration = ManualMigration(
        version: 1,
        description: 'Test migration',
        onUp: (conn, schema) async {},
        onDown: (conn, schema) async {
          downCalled = true;
        },
      );
      migration.setConnection(connection);

      await migration.down();

      expect(downCalled, true);
    });

    test('onUp receives connection and schema manager', () async {
      DatabaseConnection? receivedConn;
      SchemaManager? receivedSchema;

      final migration = ManualMigration(
        version: 1,
        description: 'Test migration',
        onUp: (conn, schema) async {
          receivedConn = conn;
          receivedSchema = schema;
        },
      );
      migration.setConnection(connection);

      await migration.up();

      expect(receivedConn, connection);
      expect(receivedSchema, isNotNull);
    });

    test('down does nothing when no onDown provided', () async {
      final migration = ManualMigration(
        version: 1,
        description: 'Test migration',
        onUp: (conn, schema) async {},
      );
      migration.setConnection(connection);

      await migration.down();
    });
  });

  group('CompositeMigration', () {
    late MockDatabaseConnection connection;

    setUp(() {
      connection = MockDatabaseConnection();
    });

    test('creates composite migration with steps', () {
      final migration = CompositeMigration(
        version: 1,
        description: 'Multiple changes',
        steps: [
          RawSqlMigration(
            version: 0,
            description: 'Step 1',
            upSql: 'CREATE TABLE test1 (id INTEGER);',
          ),
          RawSqlMigration(
            version: 0,
            description: 'Step 2',
            upSql: 'CREATE TABLE test2 (id INTEGER);',
          ),
        ],
      );

      expect(migration.version, 1);
      expect(migration.description, 'Multiple changes');
      expect(migration.steps.length, 2);
    });

    test('executes all steps in up', () async {
      final migration = CompositeMigration(
        version: 1,
        description: 'Multiple changes',
        steps: [
          RawSqlMigration(
            version: 0,
            description: 'Step 1',
            upSql: 'CREATE TABLE test1 (id INTEGER);',
          ),
          RawSqlMigration(
            version: 0,
            description: 'Step 2',
            upSql: 'CREATE TABLE test2 (id INTEGER);',
          ),
        ],
      );
      migration.setConnection(connection);

      await migration.up();

      expect(connection.executedStatements.length, 2);
      expect(connection.executedStatements[0], contains('test1'));
      expect(connection.executedStatements[1], contains('test2'));
    });

    test('executes all steps in reverse order for down', () async {
      final migration = CompositeMigration(
        version: 1,
        description: 'Multiple changes',
        steps: [
          RawSqlMigration(
            version: 0,
            description: 'Step 1',
            upSql: 'CREATE TABLE test1 (id INTEGER);',
            downSql: 'DROP TABLE test1;',
          ),
          RawSqlMigration(
            version: 0,
            description: 'Step 2',
            upSql: 'CREATE TABLE test2 (id INTEGER);',
            downSql: 'DROP TABLE test2;',
          ),
        ],
      );
      migration.setConnection(connection);

      await migration.down();

      expect(connection.executedStatements.length, 2);
      expect(connection.executedStatements[0], contains('test2'));
      expect(connection.executedStatements[1], contains('test1'));
    });
  });

  group('MigrationRunner', () {
    late MockDatabaseConnection connection;

    setUp(() {
      connection = MockDatabaseConnection();
    });

    test('creates migration runner with migrations', () {
      final migrations = [
        TestMigration(1, 'Migration 1'),
        TestMigration(2, 'Migration 2'),
      ];
      final runner = MigrationRunner(connection, migrations);

      expect(runner.connection, connection);
      expect(runner.migrations.length, 2);
    });

    test('runMigrations creates migrations table', () async {
      connection = MockDatabaseConnection(mockResults: []);
      final runner = MigrationRunner(connection, []);

      await runner.runMigrations();

      expect(
        connection.executedStatements.any(
          (s) => s.contains('CREATE TABLE IF NOT EXISTS __migrations__'),
        ),
        true,
      );
    });

    test('runMigrations executes unapplied migrations', () async {
      connection = MockDatabaseConnection(mockResults: []);
      final migration1 = TestMigration(1, 'Migration 1');
      final migration2 = TestMigration(2, 'Migration 2');
      final runner = MigrationRunner(connection, [migration1, migration2]);

      await runner.runMigrations();

      expect(migration1.upCalled, true);
      expect(migration2.upCalled, true);
    });

    test('runMigrations skips already applied migrations', () async {
      connection = MockDatabaseConnection(
        mockResults: [
          {'version': 1},
        ],
      );
      final migration1 = TestMigration(1, 'Migration 1');
      final migration2 = TestMigration(2, 'Migration 2');
      final runner = MigrationRunner(connection, [migration1, migration2]);

      await runner.runMigrations();

      expect(migration1.upCalled, false);
      expect(migration2.upCalled, true);
    });

    test('rollbackLast rolls back last migration', () async {
      connection = MockDatabaseConnection(
        mockResults: [
          {'version': 1},
          {'version': 2},
        ],
      );
      final migration1 = TestMigration(1, 'Migration 1');
      final migration2 = TestMigration(2, 'Migration 2');
      final runner = MigrationRunner(connection, [migration1, migration2]);

      await runner.rollbackLast();

      expect(migration2.downCalled, true);
    });

    test('runSql executes ad-hoc SQL', () async {
      final runner = MigrationRunner(connection, []);

      await runner.runSql('CREATE TABLE temp (id INTEGER);');

      expect(
        connection.executedStatements.last,
        'CREATE TABLE temp (id INTEGER);',
      );
    });

    test('runSqlStatements executes multiple SQL statements', () async {
      final runner = MigrationRunner(connection, []);

      await runner.runSqlStatements([
        'CREATE TABLE temp1 (id INTEGER);',
        'CREATE TABLE temp2 (id INTEGER);',
      ]);

      expect(connection.executedStatements.length, 2);
    });

    test(
      'runManual executes callback with connection and schema manager',
      () async {
        DatabaseConnection? receivedConn;
        SchemaManager? receivedSchema;

        final runner = MigrationRunner(connection, []);

        await runner.runManual((conn, schema) async {
          receivedConn = conn;
          receivedSchema = schema;
        });

        expect(receivedConn, connection);
        expect(receivedSchema, isNotNull);
      },
    );
  });
}
