import '../database/database_connection.dart' show DatabaseType;

/// Database configuration for @Db annotation
///
/// Used to configure database connection in the annotation
class DbConfig {
  /// Database host
  final String host;

  /// Database port
  final int port;

  /// Database name
  final String database;

  /// Database username
  final String? username;

  /// Database password
  final String? password;

  /// Database type (postgresql, mysql, sqlite)
  final DatabaseType dbType;

  /// Use SSL connection
  final bool ssl;

  const DbConfig({
    required this.host,
    required this.port,
    required this.database,
    this.username,
    this.password,
    this.dbType = DatabaseType.postgresql,
    this.ssl = false,
  });

  /// PostgreSQL configuration
  const DbConfig.postgresql({
    required this.host,
    this.port = 5432,
    required this.database,
    this.username,
    this.password,
    this.ssl = false,
  }) : dbType = DatabaseType.postgresql;

  /// MySQL configuration
  const DbConfig.mysql({
    required this.host,
    this.port = 3306,
    required this.database,
    this.username,
    this.password,
    this.ssl = false,
  }) : dbType = DatabaseType.mysql;

  /// SQLite configuration (file path as database)
  const DbConfig.sqlite({
    required this.database,
  }) : host = '',
       port = 0,
       username = null,
       password = null,
       dbType = DatabaseType.sqlite,
       ssl = false;
}

/// Database annotation for generating a database class with repositories
///
/// Example:
/// ```dart
/// @Db(
///   entities: [UserEntity, PostEntity],
///   migrationVersion: 1,
///   config: DbConfig.postgresql(
///     host: 'localhost',
///     database: 'mydb',
///     username: 'user',
///     password: 'password',
///   ),
/// )
/// class AppDatabase {
///   // Optional: override config in constructor
///   AppDatabase([DatabaseConfig? config]);
/// }
/// ```
class Db {
  /// List of entity types to include in the database
  final List<Type> entities;

  /// Current migration version
  final int migrationVersion;

  /// Database configuration (optional, can be passed to constructor)
  final DbConfig? config;

  /// Optional database name (defaults to config.database if config provided)
  final String? name;

  const Db({
    required this.entities,
    this.migrationVersion = 1,
    this.config,
    this.name,
  });
}
