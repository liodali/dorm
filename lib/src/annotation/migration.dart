import '../database/database_connection.dart' show DatabaseType;

/// Migration annotation for database schema migrations
class Migration {
  final int version;
  final String description;
  final DatabaseType dbType;

  const Migration({
    required this.version,
    required this.description,
    this.dbType = DatabaseType.postgresql,
  });
}
