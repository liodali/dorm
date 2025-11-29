import '../database/database_connection.dart' show DatabaseType;

/// Entity annotation for marking a class as a database entity
class Entity {
  final String? tableName;
  final String? description;
  final DatabaseType dbType;

  const Entity({
    this.tableName,
    this.description,
    this.dbType = DatabaseType.postgresql,
  });
}

/// Column annotation for customizing field-to-column mapping
class Column {
  final String? name;
  final bool primaryKey;
  final bool nullable;
  final bool unique;
  final String? defaultValue;
  final int? length;
  final ColumnType columnType;

  const Column({
    this.name,
    this.primaryKey = false,
    this.nullable = true,
    this.unique = false,
    this.defaultValue,
    this.length,
    this.columnType = ColumnType.text,
  });
}

/// Id annotation for marking a field as the primary key
class Id {
  final bool autoIncrement;
  final String? strategy; // SERIAL, UUID, IDENTITY, etc.

  const Id.postgres({
    this.autoIncrement = true,
    this.strategy = 'SERIAL',
  });
  const Id.mysql({
    this.autoIncrement = true,
    this.strategy = 'AUTO_INCREMENT',
  });
  const Id.sqlite({
    this.autoIncrement = true,
    this.strategy = 'AUTOINCREMENT',
  });
  const Id({
    this.autoIncrement = true,
    this.strategy = 'AUTOINCREMENT',
  });
}

/// Index annotation for creating database indexes
class Index {
  final List<String> columns;
  final bool unique;
  final String? name;

  const Index({required this.columns, this.unique = false, this.name});
}

/// Ignore annotation for excluding a field from database mapping
class Ignore {
  const Ignore();
}

/// Column types for database mapping
enum ColumnType {
  text,
  integer,
  serial,
  bigserial,
  uuid,
  timestamp,
  boolean,
  decimal,
  json,
}
