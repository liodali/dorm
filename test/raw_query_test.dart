import 'package:test/test.dart';
import 'package:dormql/src/raw_query.dart';
import 'package:dormql/src/database/database_connection.dart';

class MockDatabaseConnection implements DatabaseConnection {
  final List<Map<String, dynamic>> mockResults;
  final int mockExecuteResult;
  String? lastExecutedSql;
  Map<String, dynamic>? lastParameters;

  MockDatabaseConnection({
    this.mockResults = const [],
    this.mockExecuteResult = 1,
  });

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    lastExecutedSql = sql;
    lastParameters = parameters;
    return mockResults;
  }

  @override
  Future<int> execute(String sql, {Map<String, dynamic>? parameters}) async {
    lastExecutedSql = sql;
    lastParameters = parameters;
    return mockExecuteResult;
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
  group('RawQuery', () {
    test('creates RawQuery with sql and parameters', () {
      final connection = MockDatabaseConnection();
      final query = RawQuery(
        connection,
        'SELECT * FROM users WHERE id = @id',
        {'id': 1},
      );

      expect(query.sql, 'SELECT * FROM users WHERE id = @id');
      expect(query.parameters, {'id': 1});
    });

    test('creates RawQuery with empty parameters by default', () {
      final connection = MockDatabaseConnection();
      final query = RawQuery(connection, 'SELECT * FROM users');

      expect(query.sql, 'SELECT * FROM users');
      expect(query.parameters, isEmpty);
    });

    group('execute', () {
      test('executes query and returns results', () async {
        final mockResults = [
          {'id': 1, 'name': 'Alice'},
          {'id': 2, 'name': 'Bob'},
        ];
        final connection = MockDatabaseConnection(mockResults: mockResults);
        final query = RawQuery(connection, 'SELECT * FROM users');

        final results = await query.execute();

        expect(results, mockResults);
        expect(connection.lastExecutedSql, 'SELECT * FROM users');
      });

      test('executes query with parameters', () async {
        final mockResults = [
          {'id': 1, 'name': 'Alice'},
        ];
        final connection = MockDatabaseConnection(mockResults: mockResults);
        final query = RawQuery(
          connection,
          'SELECT * FROM users WHERE id = @id',
          {'id': 1},
        );

        final results = await query.execute();

        expect(results, mockResults);
        expect(connection.lastParameters, {'id': 1});
      });
    });

    group('executeFirstOrDefault', () {
      test('returns first result when results exist', () async {
        final mockResults = [
          {'id': 1, 'name': 'Alice'},
          {'id': 2, 'name': 'Bob'},
        ];
        final connection = MockDatabaseConnection(mockResults: mockResults);
        final query = RawQuery(connection, 'SELECT * FROM users');

        final result = await query.executeFirstOrDefault();

        expect(result, {'id': 1, 'name': 'Alice'});
      });

      test('returns null when no results', () async {
        final connection = MockDatabaseConnection(mockResults: []);
        final query = RawQuery(
          connection,
          'SELECT * FROM users WHERE id = 999',
        );

        final result = await query.executeFirstOrDefault();

        expect(result, isNull);
      });
    });

    group('executeScalar', () {
      test('returns first value of first result', () async {
        final mockResults = [
          {'count': 42},
        ];
        final connection = MockDatabaseConnection(mockResults: mockResults);
        final query = RawQuery(
          connection,
          'SELECT COUNT(*) as count FROM users',
        );

        final result = await query.executeScalar();

        expect(result, 42);
      });

      test('returns null when no results', () async {
        final connection = MockDatabaseConnection(mockResults: []);
        final query = RawQuery(connection, 'SELECT MAX(id) FROM users');

        final result = await query.executeScalar();

        expect(result, isNull);
      });

      test('returns first value from multiple columns', () async {
        final mockResults = [
          {'id': 1, 'name': 'Alice', 'age': 30},
        ];
        final connection = MockDatabaseConnection(mockResults: mockResults);
        final query = RawQuery(connection, 'SELECT * FROM users LIMIT 1');

        final result = await query.executeScalar();

        expect(result, 1);
      });
    });

    group('executeNonQuery', () {
      test('executes non-query and returns affected rows', () async {
        final connection = MockDatabaseConnection(mockExecuteResult: 5);
        final query = RawQuery(
          connection,
          'DELETE FROM users WHERE status = @status',
          {'status': 'inactive'},
        );

        final result = await query.executeNonQuery();

        expect(result, 5);
        expect(
          connection.lastExecutedSql,
          'DELETE FROM users WHERE status = @status',
        );
        expect(connection.lastParameters, {'status': 'inactive'});
      });

      test('executes INSERT statement', () async {
        final connection = MockDatabaseConnection(mockExecuteResult: 1);
        final query = RawQuery(
          connection,
          'INSERT INTO users (name, email) VALUES (@name, @email)',
          {'name': 'Charlie', 'email': 'charlie@example.com'},
        );

        final result = await query.executeNonQuery();

        expect(result, 1);
      });
    });

    group('toSql', () {
      test('replaces string parameters', () {
        final connection = MockDatabaseConnection();
        final query = RawQuery(
          connection,
          'SELECT * FROM users WHERE name = @name',
          {'name': 'Alice'},
        );

        final sql = query.toSql();

        expect(sql, "SELECT * FROM users WHERE name = 'Alice'");
      });

      test('replaces integer parameters', () {
        final connection = MockDatabaseConnection();
        final query = RawQuery(
          connection,
          'SELECT * FROM users WHERE id = @id',
          {'id': 42},
        );

        final sql = query.toSql();

        expect(sql, 'SELECT * FROM users WHERE id = 42');
      });

      test('replaces boolean parameters', () {
        final connection = MockDatabaseConnection();
        final query = RawQuery(
          connection,
          'SELECT * FROM users WHERE active = @active',
          {'active': true},
        );

        final sql = query.toSql();

        expect(sql, 'SELECT * FROM users WHERE active = true');
      });

      test('replaces null parameters', () {
        final connection = MockDatabaseConnection();
        final query = RawQuery(
          connection,
          'SELECT * FROM users WHERE deleted_at = @deleted',
          {'deleted': null},
        );

        final sql = query.toSql();

        expect(sql, 'SELECT * FROM users WHERE deleted_at = NULL');
      });

      test('replaces DateTime parameters', () {
        final connection = MockDatabaseConnection();
        final dateTime = DateTime(2024, 1, 15, 10, 30);
        final query = RawQuery(
          connection,
          'SELECT * FROM users WHERE created_at > @date',
          {'date': dateTime},
        );

        final sql = query.toSql();

        expect(sql, contains('SELECT * FROM users WHERE created_at >'));
        expect(sql, contains('2024-01-15'));
      });

      test('escapes single quotes in strings', () {
        final connection = MockDatabaseConnection();
        final query = RawQuery(
          connection,
          'SELECT * FROM users WHERE name = @name',
          {'name': "O'Brien"},
        );

        final sql = query.toSql();

        expect(sql, "SELECT * FROM users WHERE name = 'O''Brien'");
      });

      test('replaces multiple parameters', () {
        final connection = MockDatabaseConnection();
        final query = RawQuery(
          connection,
          'SELECT * FROM users WHERE name = @name AND age > @age',
          {'name': 'Alice', 'age': 25},
        );

        final sql = query.toSql();

        expect(sql, "SELECT * FROM users WHERE name = 'Alice' AND age > 25");
      });

      test('handles query with no parameters', () {
        final connection = MockDatabaseConnection();
        final query = RawQuery(connection, 'SELECT * FROM users');

        final sql = query.toSql();

        expect(sql, 'SELECT * FROM users');
      });
    });
  });
}
