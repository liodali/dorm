import 'package:test/test.dart';
import 'package:dormql/src/repository.dart';
import 'package:dormql/src/column_metadata.dart';
import 'package:dormql/src/database/database_connection.dart';

class MockDatabaseConnection implements DatabaseConnection {
  final List<Map<String, dynamic>> mockResults;
  String? lastExecutedSql;
  Map<String, dynamic>? lastParameters;

  MockDatabaseConnection({this.mockResults = const []});

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

class TestEntity {
  final int id;
  final String name;

  TestEntity(this.id, this.name);
}

class TestRepository extends Repository<TestEntity> {
  TestRepository() : super('users');

  @override
  TestEntity fromRow(Map<String, dynamic> row) {
    return TestEntity(row['id'] as int, row['name'] as String);
  }

  @override
  Map<String, dynamic> toRow(TestEntity entity) {
    return {'id': entity.id, 'name': entity.name};
  }
}

void main() {
  group('QueryBuilder', () {
    late TestRepository repository;
    late MockDatabaseConnection connection;

    setUp(() {
      repository = TestRepository();
      connection = MockDatabaseConnection();
      repository.setConnection(connection);
    });

    group('Basic Query Building', () {
      test('builds simple SELECT query', () {
        final query = repository.query();
        final sql = query.toSql();

        expect(sql, 'SELECT users.* FROM users');
      });

      test('builds query with WHERE clause', () {
        final query = repository.query().where('id = @id', {'id': 1});
        final sql = query.toSql();

        expect(sql, 'SELECT users.* FROM users WHERE (id = @id)');
      });

      test('builds query with multiple WHERE clauses', () {
        final query = repository.query().where('id > @min', {'min': 10}).where(
          'id < @max',
          {'max': 100},
        );
        final sql = query.toSql();

        expect(
          sql,
          'SELECT users.* FROM users WHERE (id > @min) AND (id < @max)',
        );
      });

      test('builds query with ORDER BY', () {
        final query = repository.query().orderBy('name');
        final sql = query.toSql();

        expect(sql, 'SELECT users.* FROM users ORDER BY users.name ASC');
      });

      test('builds query with ORDER BY DESC', () {
        final query = repository.query().orderByDescending('created_at');
        final sql = query.toSql();

        expect(sql, 'SELECT users.* FROM users ORDER BY users.created_at DESC');
      });

      test('builds query with LIMIT', () {
        final query = repository.query().take(10);
        final sql = query.toSql();

        expect(sql, 'SELECT users.* FROM users LIMIT 10');
      });

      test('builds query with OFFSET', () {
        final query = repository.query().skip(5);
        final sql = query.toSql();

        expect(sql, 'SELECT users.* FROM users OFFSET 5');
      });

      test('builds query with LIMIT and OFFSET', () {
        final query = repository.query().skip(10).take(5);
        final sql = query.toSql();

        expect(sql, 'SELECT users.* FROM users OFFSET 10 LIMIT 5');
      });

      test('builds query with DISTINCT', () {
        final query = repository.query().distinct();
        final sql = query.toSql();

        expect(sql, 'SELECT DISTINCT users.* FROM users');
      });
    });

    group('WHERE Clauses', () {
      test('whereSimple builds simple equality condition', () {
        final query = repository.query().whereSimple('name', 'Alice');
        final sql = query.toSql();

        expect(sql, contains('WHERE users.name = @name_0'));
      });

      test('whereIn builds IN clause', () {
        final query = repository.query().whereIn('id', [1, 2, 3]);
        final sql = query.toSql();

        expect(
          sql,
          'SELECT users.* FROM users WHERE users.id IN (@id_0,@id_1,@id_2)',
        );
      });

      test('whereNotIn builds NOT IN clause', () {
        final query = repository.query().whereNotIn('status', [
          'deleted',
          'banned',
        ]);
        final sql = query.toSql();

        expect(
          sql,
          'SELECT users.* FROM users WHERE users.status NOT IN (@status_0,@status_1)',
        );
      });

      test('whereBetween builds BETWEEN clause', () {
        final query = repository.query().whereBetween('age', 18, 65);
        final sql = query.toSql();

        expect(
          sql,
          'SELECT users.* FROM users WHERE users.age BETWEEN @age_from AND @age_to',
        );
      });

      test('whereLike builds LIKE clause', () {
        final query = repository.query().whereLike('email', '%@example.com');
        final sql = query.toSql();

        expect(
          sql,
          'SELECT users.* FROM users WHERE users.email LIKE @email_pattern',
        );
      });

      test('whereILike builds ILIKE clause', () {
        final query = repository.query().whereILike('name', 'alice%');
        final sql = query.toSql();

        expect(
          sql,
          'SELECT users.* FROM users WHERE users.name ILIKE @name_pattern',
        );
      });

      test('whereNull builds IS NULL clause', () {
        final query = repository.query().whereNull('deleted_at');
        final sql = query.toSql();

        expect(
          sql,
          'SELECT users.* FROM users WHERE users.deleted_at IS NULL',
        );
      });

      test('whereNotNull builds IS NOT NULL clause', () {
        final query = repository.query().whereNotNull('email');
        final sql = query.toSql();

        expect(
          sql,
          'SELECT users.* FROM users WHERE users.email IS NOT NULL',
        );
      });
    });

    group('JOIN Clauses', () {
      test('innerJoin builds INNER JOIN', () {
        final query = repository.query().innerJoin(
          'posts',
          'posts.user_id = users.id',
        );
        final sql = query.toSql();

        expect(
          sql,
          'SELECT users.* FROM users INNER JOIN posts ON posts.user_id = users.id',
        );
      });

      test('leftJoin builds LEFT JOIN', () {
        final query = repository.query().leftJoin(
          'profiles',
          'profiles.user_id = users.id',
        );
        final sql = query.toSql();

        expect(
          sql,
          'SELECT users.* FROM users LEFT JOIN profiles ON profiles.user_id = users.id',
        );
      });

      test('rightJoin builds RIGHT JOIN', () {
        final query = repository.query().rightJoin(
          'orders',
          'orders.user_id = users.id',
        );
        final sql = query.toSql();

        expect(
          sql,
          'SELECT users.* FROM users RIGHT JOIN orders ON orders.user_id = users.id',
        );
      });

      test('multiple joins', () {
        final query = repository
            .query()
            .innerJoin('posts', 'posts.user_id = users.id')
            .leftJoin('comments', 'comments.post_id = posts.id');
        final sql = query.toSql();

        expect(
          sql,
          'SELECT users.* FROM users '
          'INNER JOIN posts ON posts.user_id = users.id '
          'LEFT JOIN comments ON comments.post_id = posts.id',
        );
      });
    });

    group('SELECT Clauses', () {
      test('select with SelectBuilder', () {
        final query = repository.query().select((s) {
          s.column('id');
          s.column('name');
        });
        final sql = query.toSql();

        expect(sql, 'SELECT id, name FROM users');
      });

      test('select with columns method', () {
        final query = repository.query().select((s) {
          s.columns(['id', 'name', 'email']);
        });
        final sql = query.toSql();

        expect(sql, 'SELECT id, name, email FROM users');
      });

      test('selectColumns with ColumnMetadata', () {
        final columns = [
          ColumnMetadata(
            fieldName: 'id',
            columnName: 'id',
            dartType: 'int',
            sqlType: 'INTEGER',
            isPrimaryKey: true,
            isNullable: false,
            tableName: 'users',
          ),
          ColumnMetadata(
            fieldName: 'name',
            columnName: 'name',
            dartType: 'String',
            sqlType: 'TEXT',
            isPrimaryKey: false,
            isNullable: false,
            tableName: 'users',
          ),
        ];
        final query = repository.query().selectColumns(columns);
        final sql = query.toSql();

        expect(sql, 'SELECT id, name FROM users');
      });
    });

    group('Complex Queries', () {
      test('builds complex query with all clauses', () {
        final query = repository
            .query()
            .select((s) => s.columns(['id', 'name', 'email']))
            .where('status = @status', {'status': 'active'})
            .whereNotNull('email')
            .innerJoin('posts', 'posts.user_id = users.id')
            .orderBy('name')
            .orderByDescending('created_at')
            .skip(10)
            .take(5)
            .distinct();

        final sql = query.toSql();

        expect(sql, contains('SELECT DISTINCT'));
        expect(sql, contains('id, name, email'));
        expect(sql, contains('FROM users'));
        expect(sql, contains('INNER JOIN posts'));
        expect(sql, contains('WHERE'));
        expect(sql, contains('status = @status'));
        expect(sql, contains('users.email IS NOT NULL'));
        expect(sql, contains('ORDER BY'));
        expect(sql, contains('OFFSET 10'));
        expect(sql, contains('LIMIT 5'));
      });
    });

    group('Execution Methods', () {
      test('toList executes query and returns entities', () async {
        connection = MockDatabaseConnection(
          mockResults: [
            {'id': 1, 'name': 'Alice'},
            {'id': 2, 'name': 'Bob'},
          ],
        );
        repository.setConnection(connection);

        final results = await repository.query().toList();

        expect(results.length, 2);
        expect(results[0].id, 1);
        expect(results[0].name, 'Alice');
        expect(results[1].id, 2);
        expect(results[1].name, 'Bob');
      });

      test('firstOrDefault returns first result', () async {
        connection = MockDatabaseConnection(
          mockResults: [
            {'id': 1, 'name': 'Alice'},
            {'id': 2, 'name': 'Bob'},
          ],
        );
        repository.setConnection(connection);

        final result = await repository.query().firstOrDefault();

        expect(result, isNotNull);
        expect(result!.id, 1);
        expect(result.name, 'Alice');
      });

      test('firstOrDefault returns null when no results', () async {
        connection = MockDatabaseConnection(mockResults: []);
        repository.setConnection(connection);

        final result = await repository.query().firstOrDefault();

        expect(result, isNull);
      });

      test('first returns first result', () async {
        connection = MockDatabaseConnection(
          mockResults: [
            {'id': 1, 'name': 'Alice'},
          ],
        );
        repository.setConnection(connection);

        final result = await repository.query().first();

        expect(result.id, 1);
        expect(result.name, 'Alice');
      });

      test('first throws when no results', () async {
        connection = MockDatabaseConnection(mockResults: []);
        repository.setConnection(connection);

        expect(
          () => repository.query().first(),
          throwsA(isA<Exception>()),
        );
      });

      test('countSql returns count', () async {
        connection = MockDatabaseConnection(
          mockResults: [
            {'count': 42},
          ],
        );
        repository.setConnection(connection);

        final count = await repository.query().countSql();

        expect(count, 42);
        expect(connection.lastExecutedSql, contains('COUNT(*)'));
      });

      test('any returns true when results exist', () async {
        connection = MockDatabaseConnection(
          mockResults: [
            {'count': 5},
          ],
        );
        repository.setConnection(connection);

        final hasResults = await repository.query().any();

        expect(hasResults, true);
      });

      test('any returns false when no results', () async {
        connection = MockDatabaseConnection(
          mockResults: [
            {'count': 0},
          ],
        );
        repository.setConnection(connection);

        final hasResults = await repository.query().any();

        expect(hasResults, false);
      });

      test('max returns maximum value', () async {
        connection = MockDatabaseConnection(
          mockResults: [
            {'max_value': 100},
          ],
        );
        repository.setConnection(connection);

        final maxValue = await repository.query().max('age');

        expect(maxValue, 100);
        expect(connection.lastExecutedSql, contains('MAX(users.age)'));
      });

      test('min returns minimum value', () async {
        connection = MockDatabaseConnection(
          mockResults: [
            {'min_value': 18},
          ],
        );
        repository.setConnection(connection);

        final minValue = await repository.query().min('age');

        expect(minValue, 18);
        expect(connection.lastExecutedSql, contains('MIN(users.age)'));
      });

      test('sum returns sum of values', () async {
        connection = MockDatabaseConnection(
          mockResults: [
            {'sum_value': 1500},
          ],
        );
        repository.setConnection(connection);

        final sumValue = await repository.query().sum('salary');

        expect(sumValue, 1500);
        expect(connection.lastExecutedSql, contains('SUM(users.salary)'));
      });

      test('avg returns average value', () async {
        connection = MockDatabaseConnection(
          mockResults: [
            {'avg_value': 35.5},
          ],
        );
        repository.setConnection(connection);

        final avgValue = await repository.query().avg('age');

        expect(avgValue, 35.5);
        expect(connection.lastExecutedSql, contains('AVG(users.age)'));
      });

      test('aggregate functions return null when no results', () async {
        connection = MockDatabaseConnection(mockResults: []);
        repository.setConnection(connection);

        final maxValue = await repository.query().max('age');
        expect(maxValue, isNull);
      });
    });

    group('Include (Eager Loading)', () {
      test('include adds relationship to includes list', () {
        final query = repository.query().include('posts');

        expect(query, isNotNull);
      });

      test('multiple includes', () {
        final query = repository.query().include('posts').include('profile');

        expect(query, isNotNull);
      });
    });
  });

  group('SelectBuilder', () {
    late TestRepository repository;

    setUp(() {
      repository = TestRepository();
      repository.setConnection(MockDatabaseConnection());
    });

    test('column adds single column', () {
      final query = repository.query().select((s) {
        s.column('id');
      });
      final sql = query.toSql();

      expect(sql, 'SELECT id FROM users');
    });

    test('columns adds multiple columns', () {
      final query = repository.query().select((s) {
        s.columns(['id', 'name', 'email']);
      });
      final sql = query.toSql();

      expect(sql, 'SELECT id, name, email FROM users');
    });

    test('columnMeta adds column from ColumnMetadata', () {
      final column = ColumnMetadata(
        fieldName: 'id',
        columnName: 'id',
        dartType: 'int',
        sqlType: 'INTEGER',
        isPrimaryKey: true,
        isNullable: false,
        tableName: 'users',
      );
      final query = repository.query().select((s) {
        s.columnMeta(column);
      });
      final sql = query.toSql();

      expect(sql, 'SELECT id FROM users');
    });

    test('columnsMeta adds multiple columns from ColumnMetadata', () {
      final columns = [
        ColumnMetadata(
          fieldName: 'id',
          columnName: 'id',
          dartType: 'int',
          sqlType: 'INTEGER',
          isPrimaryKey: true,
          isNullable: false,
          tableName: 'users',
        ),
        ColumnMetadata(
          fieldName: 'name',
          columnName: 'name',
          dartType: 'String',
          sqlType: 'TEXT',
          isPrimaryKey: false,
          isNullable: false,
          tableName: 'users',
        ),
      ];
      final query = repository.query().select((s) {
        s.columnsMeta(columns);
      });
      final sql = query.toSql();

      expect(sql, 'SELECT id, name FROM users');
    });

    test('mixing column methods', () {
      final column = ColumnMetadata(
        fieldName: 'createdAt',
        columnName: 'created_at',
        dartType: 'DateTime',
        sqlType: 'TIMESTAMP',
        isPrimaryKey: false,
        isNullable: false,
        tableName: 'users',
      );
      final query = repository.query().select((s) {
        s.column('id');
        s.columns(['name', 'email']);
        s.columnMeta(column);
      });
      final sql = query.toSql();

      expect(sql, 'SELECT id, name, email, created_at FROM users');
    });
  });
}
