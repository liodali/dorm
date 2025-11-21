import 'dart:async';
import 'package:sqlite3/sqlite3.dart' hide DatabaseConfig;
import 'database_connection.dart';

/// SQLite implementation of DatabaseConnection
class SQLiteConnection implements DatabaseConnection {
  final DatabaseConfig config;
  Database? _database;
  bool _isOpen = false;

  SQLiteConnection(this.config) {
    if (config.type != DatabaseType.sqlite) {
      throw ArgumentError('Config must be for SQLite');
    }
  }

  /// Open connection
  Future<void> open() async {
    if (_isOpen) return;

    _database = sqlite3.open(config.filePath!);
    _isOpen = true;
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    await _ensureOpen();

    // Convert named parameters (@param) to positional (?)
    final paramList = <dynamic>[];
    var convertedSql = sql;

    if (parameters != null && parameters.isNotEmpty) {
      for (var key in parameters.keys) {
        convertedSql = convertedSql.replaceAll('@$key', '?');
        paramList.add(parameters[key]);
      }
    }

    final resultSet = _database!.select(convertedSql, paramList);
    return resultSet.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  @override
  Future<int> execute(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    await _ensureOpen();

    // Convert named parameters (@param) to positional (?)
    final paramList = <dynamic>[];
    var convertedSql = sql;

    if (parameters != null && parameters.isNotEmpty) {
      for (var key in parameters.keys) {
        convertedSql = convertedSql.replaceAll('@$key', '?');
        paramList.add(parameters[key]);
      }
    }

    _database!.execute(convertedSql, paramList);
    return _database!.lastInsertRowId;
  }

  @override
  Future<List<List<dynamic>>> rawQuery(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    await _ensureOpen();

    // Convert named parameters (@param) to positional (?)
    final paramList = <dynamic>[];
    var convertedSql = sql;

    if (parameters != null && parameters.isNotEmpty) {
      for (var key in parameters.keys) {
        convertedSql = convertedSql.replaceAll('@$key', '?');
        paramList.add(parameters[key]);
      }
    }

    final resultSet = _database!.select(convertedSql, paramList);
    return resultSet.map((row) => row.values.toList()).toList();
  }

  @override
  Future<DatabaseTransaction> beginTransaction() async {
    await _ensureOpen();
    return SQLiteTransaction(_database!);
  }

  @override
  Future<void> close() async {
    if (_database != null && _isOpen) {
      _database!.dispose();
      _isOpen = false;
      _database = null;
    }
  }

  @override
  bool get isOpen => _isOpen;

  @override
  DatabaseType get databaseType => DatabaseType.sqlite;

  Future<void> _ensureOpen() async {
    if (!_isOpen) {
      await open();
    }
  }
}

/// SQLite transaction implementation
class SQLiteTransaction implements DatabaseTransaction {
  final Database _database;
  bool _isActive = true;
  bool _transactionStarted = false;

  SQLiteTransaction(this._database) {
    _database.execute('BEGIN TRANSACTION');
    _transactionStarted = true;
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    _ensureActive();

    // Convert named parameters (@param) to positional (?)
    final paramList = <dynamic>[];
    var convertedSql = sql;

    if (parameters != null && parameters.isNotEmpty) {
      for (var key in parameters.keys) {
        convertedSql = convertedSql.replaceAll('@$key', '?');
        paramList.add(parameters[key]);
      }
    }

    final resultSet = _database.select(convertedSql, paramList);
    return resultSet.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  @override
  Future<int> execute(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    _ensureActive();

    // Convert named parameters (@param) to positional (?)
    final paramList = <dynamic>[];
    var convertedSql = sql;

    if (parameters != null && parameters.isNotEmpty) {
      for (var key in parameters.keys) {
        convertedSql = convertedSql.replaceAll('@$key', '?');
        paramList.add(parameters[key]);
      }
    }

    _database.execute(convertedSql, paramList);
    return _database.lastInsertRowId;
  }

  @override
  Future<void> commit() async {
    _ensureActive();
    if (_transactionStarted) {
      _database.execute('COMMIT');
      _transactionStarted = false;
    }
    _isActive = false;
  }

  @override
  Future<void> rollback() async {
    _ensureActive();
    if (_transactionStarted) {
      _database.execute('ROLLBACK');
      _transactionStarted = false;
    }
    _isActive = false;
  }

  void _ensureActive() {
    if (!_isActive) {
      throw StateError('Transaction is not active');
    }
  }
}
