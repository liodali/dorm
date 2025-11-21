/// DORM - Dart Object-Relational Mapping
///
/// A powerful ORM for Dart inspired by Hibernate and Entity Framework.
/// Supports PostgreSQL, MySQL, and SQLite with LINQ-style queries.
library;

// Core components
export 'src/annotation.dart';
export 'src/repository.dart';
export 'src/query_builder.dart';
export 'src/raw_query.dart';
export 'src/stored_procedure.dart';
export 'src/migration.dart';

// Database connection
export 'src/database/database_connection.dart';
export 'src/database/database_factory.dart';
export 'src/database/postgresql_connection.dart';
export 'src/database/mysql_connection.dart';
export 'src/database/sqlite_connection.dart';
