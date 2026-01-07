import 'package:test/test.dart';
import 'package:dormql/src/database/database_connection.dart';

void main() {
  group('DatabaseConfig', () {
    group('PostgreSQL Configuration', () {
      test('creates PostgreSQL config with required parameters', () {
        final config = DatabaseConfig.postgresql(
          host: 'localhost',
          port: 5432,
          database: 'testdb',
          username: 'user',
          password: 'pass',
        );

        expect(config.type, DatabaseType.postgresql);
        expect(config.host, 'localhost');
        expect(config.port, 5432);
        expect(config.database, 'testdb');
        expect(config.username, 'user');
        expect(config.password, 'pass');
        expect(config.useSSL, false);
        expect(config.maxConnections, 10);
        expect(config.connectionTimeout, const Duration(seconds: 30));
      });

      test('creates PostgreSQL config with custom SSL and connections', () {
        final config = DatabaseConfig.postgresql(
          host: 'db.example.com',
          port: 5432,
          database: 'proddb',
          username: 'admin',
          password: 'secret',
          useSSL: true,
          maxConnections: 20,
          connectionTimeout: const Duration(seconds: 60),
        );

        expect(config.useSSL, true);
        expect(config.maxConnections, 20);
        expect(config.connectionTimeout, const Duration(seconds: 60));
      });

      test('toString returns correct format for PostgreSQL', () {
        final config = DatabaseConfig.postgresql(
          host: 'localhost',
          port: 5432,
          database: 'testdb',
          username: 'user',
          password: 'pass',
        );

        expect(config.toString(), 'PostgreSQL: user@localhost:5432/testdb');
      });
    });

    group('MySQL Configuration', () {
      test('creates MySQL config with required parameters', () {
        final config = DatabaseConfig.mysql(
          host: 'localhost',
          port: 3306,
          database: 'testdb',
          username: 'root',
          password: 'pass',
        );

        expect(config.type, DatabaseType.mysql);
        expect(config.host, 'localhost');
        expect(config.port, 3306);
        expect(config.database, 'testdb');
        expect(config.username, 'root');
        expect(config.password, 'pass');
      });

      test('creates MySQL config with custom parameters', () {
        final config = DatabaseConfig.mysql(
          host: 'mysql.example.com',
          port: 3307,
          database: 'proddb',
          username: 'admin',
          password: 'secret',
          useSSL: true,
          maxConnections: 50,
        );

        expect(config.useSSL, true);
        expect(config.maxConnections, 50);
      });

      test('toString returns correct format for MySQL', () {
        final config = DatabaseConfig.mysql(
          host: 'localhost',
          port: 3306,
          database: 'testdb',
          username: 'root',
          password: 'pass',
        );

        expect(config.toString(), 'MySQL: root@localhost:3306/testdb');
      });
    });

    group('SQLite Configuration', () {
      test('creates SQLite config with file path', () {
        final config = DatabaseConfig.sqlite(filePath: '/tmp/test.db');

        expect(config.type, DatabaseType.sqlite);
        expect(config.filePath, '/tmp/test.db');
        expect(config.host, null);
        expect(config.port, null);
        expect(config.database, null);
        expect(config.username, null);
        expect(config.password, null);
      });

      test('toString returns correct format for SQLite', () {
        final config = DatabaseConfig.sqlite(filePath: '/tmp/test.db');

        expect(config.toString(), 'SQLite: /tmp/test.db');
      });
    });

    group('General Constructor', () {
      test('creates config with all parameters', () {
        final config = DatabaseConfig(
          type: DatabaseType.postgresql,
          host: 'localhost',
          port: 5432,
          database: 'testdb',
          username: 'user',
          password: 'pass',
          useSSL: true,
          maxConnections: 15,
          connectionTimeout: const Duration(seconds: 45),
          additionalParams: {'schema': 'public'},
        );

        expect(config.type, DatabaseType.postgresql);
        expect(config.additionalParams, {'schema': 'public'});
      });

      test('creates config with minimal parameters', () {
        final config = DatabaseConfig(
          type: DatabaseType.sqlite,
          filePath: '/tmp/test.db',
        );

        expect(config.type, DatabaseType.sqlite);
        expect(config.filePath, '/tmp/test.db');
        expect(config.useSSL, false);
        expect(config.maxConnections, 10);
      });
    });
  });

  group('DatabaseType', () {
    test('has correct enum values', () {
      expect(DatabaseType.values.length, 3);
      expect(DatabaseType.values, contains(DatabaseType.postgresql));
      expect(DatabaseType.values, contains(DatabaseType.mysql));
      expect(DatabaseType.values, contains(DatabaseType.sqlite));
    });
  });
}
