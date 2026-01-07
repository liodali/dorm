import 'package:test/test.dart';
import 'package:dormql/src/stored_procedure.dart';
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

void main() {
  group('StoredProcedure', () {
    test('creates stored procedure with name', () {
      final proc = StoredProcedure(name: 'get_users');

      expect(proc.name, 'get_users');
      expect(proc.schema, 'public');
      expect(proc.parameters, isEmpty);
    });

    test('creates stored procedure with custom schema', () {
      final proc = StoredProcedure(name: 'get_users', schema: 'custom_schema');

      expect(proc.schema, 'custom_schema');
    });

    test('creates stored procedure with parameters', () {
      final proc = StoredProcedure(
        name: 'get_user_by_id',
        parameters: [1],
      );

      expect(proc.parameters, [1]);
    });

    test('creates stored procedure with connection', () {
      final connection = MockDatabaseConnection();
      final proc = StoredProcedure(
        name: 'get_users',
        connection: connection,
      );

      expect(proc, isNotNull);
    });

    test('setConnection sets the connection', () {
      final connection = MockDatabaseConnection();
      final proc = StoredProcedure(name: 'get_users');

      proc.setConnection(connection);

      expect(proc, isNotNull);
    });

    group('execute', () {
      test('executes stored procedure and returns results', () async {
        final mockResults = [
          {'id': 1, 'name': 'Alice'},
          {'id': 2, 'name': 'Bob'},
        ];
        final connection = MockDatabaseConnection(mockResults: mockResults);
        final proc = StoredProcedure(
          name: 'get_all_users',
          connection: connection,
        );

        final results = await proc.execute();

        expect(results, mockResults);
        expect(
          connection.lastExecutedSql,
          'SELECT * FROM public.get_all_users()',
        );
      });

      test('executes stored procedure with parameters', () async {
        final mockResults = [
          {'id': 1, 'name': 'Alice'},
        ];
        final connection = MockDatabaseConnection(mockResults: mockResults);
        final proc = StoredProcedure(
          name: 'get_user_by_id',
          parameters: [1],
          connection: connection,
        );

        final results = await proc.execute();

        expect(results, mockResults);
        expect(
          connection.lastExecutedSql,
          'SELECT * FROM public.get_user_by_id(@param0)',
        );
        expect(connection.lastParameters, {'param0': 1});
      });

      test('executes stored procedure with multiple parameters', () async {
        final connection = MockDatabaseConnection();
        final proc = StoredProcedure(
          name: 'search_users',
          parameters: ['Alice', 25, true],
          connection: connection,
        );

        await proc.execute();

        expect(
          connection.lastExecutedSql,
          'SELECT * FROM public.search_users(@param0,@param1,@param2)',
        );
        expect(connection.lastParameters, {
          'param0': 'Alice',
          'param1': 25,
          'param2': true,
        });
      });

      test('executes stored procedure with custom schema', () async {
        final connection = MockDatabaseConnection();
        final proc = StoredProcedure(
          name: 'get_users',
          schema: 'analytics',
          connection: connection,
        );

        await proc.execute();

        expect(
          connection.lastExecutedSql,
          'SELECT * FROM analytics.get_users()',
        );
      });

      test('throws error when connection not set', () async {
        final proc = StoredProcedure(name: 'get_users');

        expect(
          () => proc.execute(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Connection not set'),
            ),
          ),
        );
      });
    });

    group('executeScalar', () {
      test('returns first value of first result', () async {
        final mockResults = [
          {'count': 42},
        ];
        final connection = MockDatabaseConnection(mockResults: mockResults);
        final proc = StoredProcedure(
          name: 'count_users',
          connection: connection,
        );

        final result = await proc.executeScalar();

        expect(result, 42);
      });

      test('returns null when no results', () async {
        final connection = MockDatabaseConnection(mockResults: []);
        final proc = StoredProcedure(
          name: 'get_max_id',
          connection: connection,
        );

        final result = await proc.executeScalar();

        expect(result, isNull);
      });
    });

    group('executeNonQuery', () {
      test('executes stored procedure without returning results', () async {
        final connection = MockDatabaseConnection();
        final proc = StoredProcedure(
          name: 'update_user_status',
          parameters: [1, 'active'],
          connection: connection,
        );

        await proc.executeNonQuery();

        expect(
          connection.lastExecutedSql,
          'CALL public.update_user_status(@param0,@param1)',
        );
        expect(connection.lastParameters, {'param0': 1, 'param1': 'active'});
      });

      test('throws error when connection not set', () async {
        final proc = StoredProcedure(name: 'update_status');

        expect(
          () => proc.executeNonQuery(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Connection not set'),
            ),
          ),
        );
      });
    });
  });

  group('StoredProcedureBuilder', () {
    test('builds stored procedure with name', () {
      final connection = MockDatabaseConnection();
      final builder = StoredProcedureBuilder(connection, 'get_users');

      final proc = builder.build();

      expect(proc.name, 'get_users');
      expect(proc.schema, 'public');
      expect(proc.parameters, isEmpty);
    });

    test('builds stored procedure with custom schema', () {
      final connection = MockDatabaseConnection();
      final builder = StoredProcedureBuilder(
        connection,
        'get_users',
      ).withSchema('analytics');

      final proc = builder.build();

      expect(proc.schema, 'analytics');
    });

    test('builds stored procedure with single parameter', () {
      final connection = MockDatabaseConnection();
      final builder = StoredProcedureBuilder(
        connection,
        'get_user_by_id',
      ).addParameter(1);

      final proc = builder.build();

      expect(proc.parameters, [1]);
    });

    test('builds stored procedure with multiple parameters', () {
      final connection = MockDatabaseConnection();
      final builder = StoredProcedureBuilder(
        connection,
        'search_users',
      ).addParameter('Alice').addParameter(25).addParameter(true);

      final proc = builder.build();

      expect(proc.parameters, ['Alice', 25, true]);
    });

    test('builds stored procedure with schema and parameters', () {
      final connection = MockDatabaseConnection();
      final builder = StoredProcedureBuilder(
        connection,
        'get_active_users',
      ).withSchema('reporting').addParameter('active').addParameter(100);

      final proc = builder.build();

      expect(proc.name, 'get_active_users');
      expect(proc.schema, 'reporting');
      expect(proc.parameters, ['active', 100]);
    });

    test('builder methods return builder for chaining', () {
      final connection = MockDatabaseConnection();
      final builder = StoredProcedureBuilder(connection, 'test_proc');

      expect(builder.withSchema('test'), isA<StoredProcedureBuilder>());
      expect(builder.addParameter(1), isA<StoredProcedureBuilder>());
    });
  });
}
