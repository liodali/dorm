import 'dart:async';
import 'package:mysql_client_plus/mysql_client_plus.dart' as mysql;
import 'database_connection.dart';

/// MySQL implementation of DatabaseConnection
/// Uses mysql_client_plus package for MySQL connectivity
class MySQLConnection implements DatabaseConnection {
  final DatabaseConfig config;
  mysql.MySQLConnection? _connection;
  bool _isOpen = false;

  MySQLConnection(this.config) {
    if (config.type != DatabaseType.mysql) {
      throw ArgumentError('Config must be for MySQL');
    }
  }

  /// Open connection
  Future<void> open() async {
    if (_isOpen) return;

    _connection = await mysql.MySQLConnection.createConnection(
      host: config.host!,
      port: config.port!,
      userName: config.username!,
      password: config.password!,
      databaseName: config.database!,
      secure: false,
    );

    await _connection!.connect();
    _isOpen = true;
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    await _ensureOpen();

    final result = await _connection!.execute(
      sql,
      parameters ?? {},
    );

    final rows = <Map<String, dynamic>>[];
    for (final row in result.rows) {
      rows.add(row.assoc());
    }
    return rows;
  }

  @override
  Future<int> execute(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    await _ensureOpen();

    final result = await _connection!.execute(
      sql,
      parameters ?? {},
    );

    return result.affectedRows.toInt();
  }

  @override
  Future<List<List<dynamic>>> rawQuery(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    await _ensureOpen();

    final result = await _connection!.execute(
      sql,
      parameters ?? {},
    );

    final rows = <List<dynamic>>[];
    for (final row in result.rows) {
      rows.add(row.typedAssoc().values.toList());
    }
    return rows;
  }

  @override
  Future<DatabaseTransaction> beginTransaction() async {
    await _ensureOpen();
    return MySQLTransaction(_connection!);
  }

  @override
  Future<void> close() async {
    if (_connection != null && _isOpen) {
      await _connection!.close();
      _isOpen = false;
      _connection = null;
    }
  }

  @override
  bool get isOpen => _isOpen;

  @override
  DatabaseType get databaseType => DatabaseType.mysql;

  Future<void> _ensureOpen() async {
    if (!_isOpen) {
      await open();
    }
  }
}

/// MySQL transaction implementation
class MySQLTransaction implements DatabaseTransaction {
  final mysql.MySQLConnection _connection;
  bool _isActive = true;
  bool _transactionStarted = false;

  MySQLTransaction(this._connection);

  Future<void> _ensureTransactionStarted() async {
    if (!_transactionStarted) {
      await _connection.execute('START TRANSACTION');
      _transactionStarted = true;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    _ensureActive();
    await _ensureTransactionStarted();

    final result = await _connection.execute(
      sql,
      parameters ?? {},
    );

    final rows = <Map<String, dynamic>>[];
    for (final row in result.rows) {
      rows.add(row.assoc());
    }
    return rows;
  }

  @override
  Future<int> execute(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    _ensureActive();
    await _ensureTransactionStarted();

    final result = await _connection.execute(
      sql,
      parameters ?? {},
    );

    return result.affectedRows.toInt();
  }

  @override
  Future<void> commit() async {
    _ensureActive();
    if (_transactionStarted) {
      await _connection.execute('COMMIT');
    }
    _isActive = false;
  }

  @override
  Future<void> rollback() async {
    _ensureActive();
    if (_transactionStarted) {
      await _connection.execute('ROLLBACK');
    }
    _isActive = false;
  }

  void _ensureActive() {
    if (!_isActive) {
      throw StateError('Transaction is not active');
    }
  }
}
