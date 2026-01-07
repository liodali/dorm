import 'dart:async';
import 'package:postgres/postgres.dart';
import 'database_connection.dart';

/// PostgreSQL implementation of DatabaseConnection
class PostgreSQLConnection implements DatabaseConnection {
  final DatabaseConfig config;
  Connection? _connection;
  bool _isOpen = false;

  PostgreSQLConnection(this.config) {
    if (config.type != DatabaseType.postgresql) {
      throw ArgumentError('Config must be for PostgreSQL');
    }
  }

  /// Open connection
  Future<void> open() async {
    if (_isOpen) return;

    final sslMode = config.useSSL ? SslMode.require : SslMode.disable;

    _connection = await Connection.open(
      Endpoint(
        host: config.host!,
        port: config.port!,
        database: config.database!,
        username: config.username!,
        password: config.password!,
      ),
      settings: ConnectionSettings(
        sslMode: sslMode,
        connectTimeout: config.connectionTimeout,
      ),
    );
    _isOpen = true;
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    await _ensureOpen();

    final result = await _connection!.execute(
      Sql.named(sql),
      parameters: parameters ?? {},
    );

    return result.map((row) {
      final map = <String, dynamic>{};
      for (var i = 0; i < row.length; i++) {
        final name = result.schema.columns[i].columnName ?? 'col_$i';
        map[name] = row[i];
      }
      return map;
    }).toList();
  }

  @override
  Future<int> execute(String sql, {Map<String, dynamic>? parameters}) async {
    await _ensureOpen();

    final result = await _connection!.execute(
      Sql.named(sql),
      parameters: parameters ?? {},
    );

    return result.affectedRows;
  }

  @override
  Future<List<List<dynamic>>> rawQuery(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    await _ensureOpen();

    final result = await _connection!.execute(
      Sql.named(sql),
      parameters: parameters ?? {},
    );

    return result.map((row) => row.toList()).toList();
  }

  @override
  Future<DatabaseTransaction> beginTransaction() async {
    await _ensureOpen();
    return PostgreSQLTransaction(_connection!);
  }

  @override
  Future<void> close() async {
    if (_connection != null && _isOpen) {
      await _connection!.close();
      _isOpen = false;
    }
  }

  @override
  bool get isOpen => _isOpen;

  @override
  DatabaseType get databaseType => DatabaseType.postgresql;

  Future<void> _ensureOpen() async {
    if (!_isOpen) {
      await open();
    }
  }
}

/// PostgreSQL transaction implementation
class PostgreSQLTransaction implements DatabaseTransaction {
  final Connection _connection;
  bool _isActive = true;

  PostgreSQLTransaction(this._connection);

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    _ensureActive();

    final result = await _connection.execute(
      Sql.named(sql),
      parameters: parameters ?? {},
    );

    return result.map((row) {
      final map = <String, dynamic>{};
      for (var i = 0; i < row.length; i++) {
        final name = result.schema.columns[i].columnName ?? 'col_$i';
        map[name] = row[i];
      }
      return map;
    }).toList();
  }

  @override
  Future<int> execute(String sql, {Map<String, dynamic>? parameters}) async {
    _ensureActive();

    final result = await _connection.execute(
      Sql.named(sql),
      parameters: parameters ?? {},
    );

    return result.affectedRows;
  }

  @override
  Future<void> commit() async {
    _ensureActive();
    await _connection.execute('COMMIT;');
    _isActive = false;
  }

  @override
  Future<void> rollback() async {
    _ensureActive();
    await _connection.execute('ROLLBACK;');
    _isActive = false;
  }

  void _ensureActive() {
    if (!_isActive) {
      throw StateError('Transaction is not active');
    }
  }
}
