import 'dart:async';

/// Abstract database connection interface
/// Supports PostgreSQL, MySQL, and SQLite
abstract class DatabaseConnection {
  /// Execute a query and return mapped results
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? parameters,
  });

  /// Execute a non-query statement (INSERT, UPDATE, DELETE)
  Future<int> execute(String sql, {Map<String, dynamic>? parameters});

  /// Execute a query and return raw results
  Future<List<List<dynamic>>> rawQuery(
    String sql, {
    Map<String, dynamic>? parameters,
  });

  /// Begin a transaction
  Future<DatabaseTransaction> beginTransaction();

  /// Close the connection
  Future<void> close();

  /// Check if connection is open
  bool get isOpen;

  /// Get database type
  DatabaseType get databaseType;
}

/// Transaction interface
abstract class DatabaseTransaction {
  /// Execute a query within transaction
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? parameters,
  });

  /// Execute a non-query within transaction
  Future<int> execute(String sql, {Map<String, dynamic>? parameters});

  /// Commit the transaction
  Future<void> commit();

  /// Rollback the transaction
  Future<void> rollback();
}

/// Database types supported
enum DatabaseType { postgresql, mysql, sqlite }

/// Database configuration
class DatabaseConfig {
  final DatabaseType type;
  final String? host;
  final int? port;
  final String? database;
  final String? username;
  final String? password;
  final String? filePath; // For SQLite
  final bool useSSL;
  final int maxConnections;
  final Duration connectionTimeout;
  final Map<String, dynamic>? additionalParams;

  const DatabaseConfig({
    required this.type,
    this.host,
    this.port,
    this.database,
    this.username,
    this.password,
    this.filePath,
    this.useSSL = false,
    this.maxConnections = 10,
    this.connectionTimeout = const Duration(seconds: 30),
    this.additionalParams,
  });

  /// PostgreSQL configuration
  factory DatabaseConfig.postgresql({
    required String host,
    required int port,
    required String database,
    required String username,
    required String password,
    bool useSSL = false,
    int maxConnections = 10,
    Duration connectionTimeout = const Duration(seconds: 30),
  }) {
    return DatabaseConfig(
      type: DatabaseType.postgresql,
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
      useSSL: useSSL,
      maxConnections: maxConnections,
      connectionTimeout: connectionTimeout,
    );
  }

  /// MySQL configuration
  factory DatabaseConfig.mysql({
    required String host,
    required int port,
    required String database,
    required String username,
    required String password,
    bool useSSL = false,
    int maxConnections = 10,
    Duration connectionTimeout = const Duration(seconds: 30),
  }) {
    return DatabaseConfig(
      type: DatabaseType.mysql,
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
      useSSL: useSSL,
      maxConnections: maxConnections,
      connectionTimeout: connectionTimeout,
    );
  }

  /// SQLite configuration
  factory DatabaseConfig.sqlite({required String filePath}) {
    return DatabaseConfig(type: DatabaseType.sqlite, filePath: filePath);
  }

  @override
  String toString() {
    switch (type) {
      case DatabaseType.postgresql:
        return 'PostgreSQL: $username@$host:$port/$database';
      case DatabaseType.mysql:
        return 'MySQL: $username@$host:$port/$database';
      case DatabaseType.sqlite:
        return 'SQLite: $filePath';
    }
  }
}
