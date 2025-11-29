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

/// OneToMany relationship annotation
///
/// Defines a one-to-many or many-to-one relationship between entities.
/// Use `isOwning: true` on the side that owns the foreign key column.
///
/// Example:
/// ```dart
/// // In UserEntity (the "one" side - inverse)
/// @OneToMany(
///   targetEntity: PostEntity,
///   mappedBy: 'author',  // Field name in PostEntity that references UserEntity
/// )
/// List<PostEntity>? posts;
///
/// // In PostEntity (the "many" side - owning, has FK column)
/// @OneToMany(
///   targetEntity: UserEntity,
///   foreignKey: 'user_id',  // FK column name in this table
///   referencedColumn: 'id', // Referenced column in UserEntity
///   isOwning: true,
/// )
/// UserEntity? author;
/// ```
class OneToMany {
  /// The target entity type for this relationship
  final Type targetEntity;

  /// Field name in the target entity that owns the relationship
  /// Used on the inverse side (the "one" side) to reference the owning side's field
  final String? mappedBy;

  /// Foreign key column name in this entity's table
  /// Required on the owning side (the side that has the FK column)
  final String? foreignKey;

  /// Referenced column in the target entity (usually 'id')
  final String referencedColumn;

  /// Whether this is the owning side (has the FK column)
  /// - true: This entity's table has the FK column (many-to-one direction)
  /// - false: The target entity's table has the FK column (one-to-many direction)
  final bool isOwning;

  /// Whether to cascade delete operations
  final bool cascadeDelete;

  /// Whether to lazy load the relationship
  final bool lazyLoad;

  /// Whether to eager load the relationship
  final bool eagerLoad;

  /// Whether this relationship is nullable
  final bool nullable;

  /// Action to take on delete of referenced entity
  final RelationAction onDelete;

  /// Action to take on update of referenced entity
  final RelationAction onUpdate;

  const OneToMany({
    required this.targetEntity,
    this.mappedBy,
    this.foreignKey,
    this.referencedColumn = 'id',
    this.isOwning = false,
    this.cascadeDelete = false,
    this.lazyLoad = true,
    this.eagerLoad = false,
    this.nullable = true,
    this.onDelete = RelationAction.noAction,
    this.onUpdate = RelationAction.noAction,
  });
}

/// Actions for relationship constraints (used in annotations)
enum RelationAction {
  /// No action on delete/update
  noAction,

  /// Restrict delete/update if referenced
  restrict,

  /// Cascade delete/update to referencing rows
  cascade,

  /// Set to NULL on delete/update
  setNull,

  /// Set to default value on delete/update
  setDefault,
}

/// ManyToMany relationship annotation
///
/// Creates a junction table to link two entities.
///
/// Example:
/// ```dart
/// // In UserEntity
/// @ManyToMany(
///   targetEntity: RoleEntity,
///   joinTable: JoinTable(
///     name: 'user_roles',
///     joinColumn: JoinColumn(name: 'user_id', referencedColumn: 'id'),
///     inverseJoinColumn: JoinColumn(name: 'role_id', referencedColumn: 'id'),
///   ),
/// )
/// List<RoleEntity>? roles;
///
/// // In RoleEntity (inverse side)
/// @ManyToMany(
///   targetEntity: UserEntity,
///   mappedBy: 'roles',  // References the field in UserEntity
/// )
/// List<UserEntity>? users;
/// ```
class ManyToMany {
  /// The target entity type for this relationship
  final Type targetEntity;

  /// Junction table configuration (required on owning side)
  final JoinTable? joinTable;

  /// Field name in the target entity that owns the relationship (for inverse side)
  /// If set, this is the inverse side and joinTable should be null
  final String? mappedBy;

  /// Whether to cascade delete operations
  final bool cascadeDelete;

  /// Whether to lazy load the relationship
  final bool lazyLoad;

  /// Index configuration for the junction table
  final bool createIndex;

  const ManyToMany({
    required this.targetEntity,
    this.joinTable,
    this.mappedBy,
    this.cascadeDelete = false,
    this.lazyLoad = true,
    this.createIndex = true,
  });
}

/// Junction table configuration for ManyToMany relationships
class JoinTable {
  /// Name of the junction table
  final String name;

  /// Column configuration for the owning entity's foreign key
  final JoinColumn joinColumn;

  /// Column configuration for the target entity's foreign key
  final JoinColumn inverseJoinColumn;

  /// Additional indexes to create on the junction table
  final List<String>? additionalIndexes;

  const JoinTable({
    required this.name,
    required this.joinColumn,
    required this.inverseJoinColumn,
    this.additionalIndexes,
  });
}

/// Column configuration for junction table foreign keys
class JoinColumn {
  /// Column name in the junction table
  final String name;

  /// Referenced column in the source entity (usually 'id')
  final String referencedColumn;

  /// Whether this column is nullable
  final bool nullable;

  const JoinColumn({
    required this.name,
    this.referencedColumn = 'id',
    this.nullable = false,
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
