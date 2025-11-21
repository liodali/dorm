import 'database_connection.dart';
import 'postgresql_connection.dart';
import 'mysql_connection.dart';
import 'sqlite_connection.dart';

/// Factory for creating database connections
class DatabaseFactory {
  /// Create a database connection from configuration
  static Future<DatabaseConnection> createConnection(
    DatabaseConfig config,
  ) async {
    final connection = _createConnectionInstance(config);

    // Open connection based on type
    if (connection is PostgreSQLConnection) {
      await connection.open();
    } else if (connection is MySQLConnection) {
      await connection.open();
    } else if (connection is SQLiteConnection) {
      await connection.open();
    }

    return connection;
  }

  /// Create connection instance without opening
  static DatabaseConnection _createConnectionInstance(DatabaseConfig config) {
    switch (config.type) {
      case DatabaseType.postgresql:
        return PostgreSQLConnection(config);
      case DatabaseType.mysql:
        return MySQLConnection(config);
      case DatabaseType.sqlite:
        return SQLiteConnection(config);
    }
  }

  /// Create a connection pool (for future implementation)
  static Future<DatabaseConnectionPool> createPool(
    DatabaseConfig config, {
    int maxConnections = 10,
  }) async {
    return DatabaseConnectionPool(config, maxConnections: maxConnections);
  }
}

/// Connection pool for managing multiple database connections
class DatabaseConnectionPool {
  final DatabaseConfig config;
  final int maxConnections;
  final List<DatabaseConnection> _availableConnections = [];
  final List<DatabaseConnection> _usedConnections = [];
  bool _isClosed = false;

  DatabaseConnectionPool(
    this.config, {
    this.maxConnections = 10,
  });

  /// Get a connection from the pool
  Future<DatabaseConnection> getConnection() async {
    if (_isClosed) {
      throw StateError('Connection pool is closed');
    }

    // Return available connection if exists
    if (_availableConnections.isNotEmpty) {
      final connection = _availableConnections.removeLast();
      _usedConnections.add(connection);
      return connection;
    }

    // Create new connection if under limit
    if (_usedConnections.length < maxConnections) {
      final connection = await DatabaseFactory.createConnection(config);
      _usedConnections.add(connection);
      return connection;
    }

    // Wait for a connection to become available
    throw StateError(
      'Connection pool exhausted. Max connections: $maxConnections',
    );
  }

  /// Release a connection back to the pool
  Future<void> releaseConnection(DatabaseConnection connection) async {
    if (_isClosed) {
      await connection.close();
      return;
    }

    _usedConnections.remove(connection);
    _availableConnections.add(connection);
  }

  /// Close all connections in the pool
  Future<void> close() async {
    _isClosed = true;

    // Close all connections
    final allConnections = [
      ..._availableConnections,
      ..._usedConnections,
    ];

    for (final connection in allConnections) {
      await connection.close();
    }

    _availableConnections.clear();
    _usedConnections.clear();
  }

  /// Get pool statistics
  Map<String, int> get stats => {
    'available': _availableConnections.length,
    'used': _usedConnections.length,
    'total': _availableConnections.length + _usedConnections.length,
    'max': maxConnections,
  };
}
