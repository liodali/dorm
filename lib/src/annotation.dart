import 'database/database_connection.dart' show DatabaseType;

// Entity annotations
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

class Id {
  final bool autoIncrement;
  final String? strategy; // SERIAL, UUID, IDENTITY, etc.

  const Id({this.autoIncrement = true, this.strategy = 'SERIAL'});
}

// Relationship annotations
class OneToMany {
  final Type targetEntity;
  final String mappedBy;
  final bool cascadeDelete;
  final bool lazyLoad;

  const OneToMany({
    required this.targetEntity,
    required this.mappedBy,
    this.cascadeDelete = false,
    this.lazyLoad = true,
  });
}

class ManyToOne {
  final Type targetEntity;
  final bool nullable;
  final bool cascadeDelete;
  final bool eagerLoad;

  const ManyToOne({
    required this.targetEntity,
    this.nullable = true,
    this.cascadeDelete = false,
    this.eagerLoad = false,
  });
}

class ManyToMany {
  final Type targetEntity;
  final String joinTableName;
  final String inverseFieldName;

  const ManyToMany({
    required this.targetEntity,
    required this.joinTableName,
    required this.inverseFieldName,
  });
}

// Stored procedure annotation
class StoredProcedureAnnotation {
  final String name;
  final String? schema;
  final String? description;

  const StoredProcedureAnnotation({
    required this.name,
    this.schema = 'public',
    this.description,
  });
}

// Raw query annotation
class Query {
  final String sql;
  final QueryType type;
  final String? description;

  const Query({
    required this.sql,
    this.type = QueryType.select,
    this.description,
  });
}

// Migration annotation
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

// Index annotation
class Index {
  final List<String> columns;
  final bool unique;
  final String? name;

  const Index({required this.columns, this.unique = false, this.name});
}

// Ignore annotation
class Ignore {
  const Ignore();
}

// Enums
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

enum QueryType { select, insert, update, delete }
