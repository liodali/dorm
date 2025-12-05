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

/// OneToOne relationship annotation
///
/// Defines a one-to-one relationship between entities.
/// One side must be the owning side (has the FK column), the other is the inverse side.
///
/// Example:
/// ```dart
/// // In UserEntity (inverse side - no FK column)
/// @OneToOne(
///   targetEntity: ProfileEntity,
///   mappedBy: 'user',  // Field name in ProfileEntity
/// )
/// ProfileEntity? profile;
///
/// // In ProfileEntity (owning side - has FK column)
/// @OneToOne(
///   targetEntity: UserEntity,
///   foreignKey: 'user_id',
///   isOwning: true,
///   onDelete: RelationAction.cascade,
/// )
/// UserEntity? user;
/// ```
class OneToOne {
  /// The target entity type for this relationship
  final Type targetEntity;

  /// Field name in the target entity that owns the relationship
  /// Used on the inverse side to reference the owning side's field
  final String? mappedBy;

  /// Foreign key column name in this entity's table
  /// Required on the owning side (the side that has the FK column)
  final String? foreignKey;

  /// Referenced column in the target entity (usually 'id')
  final String referencedColumn;

  /// Whether this is the owning side (has the FK column)
  final bool isOwning;

  /// Whether to cascade delete operations
  final bool cascadeDelete;

  /// Whether to lazy load the relationship
  final bool lazyLoad;

  /// Whether to eager load the relationship
  final bool eagerLoad;

  /// Whether this relationship is nullable
  final bool nullable;

  /// Whether to enforce uniqueness on the FK column (ensures 1:1)
  final bool unique;

  /// Action to take on delete of referenced entity
  final RelationAction onDelete;

  /// Action to take on update of referenced entity
  final RelationAction onUpdate;

  const OneToOne({
    required this.targetEntity,
    this.mappedBy,
    this.foreignKey,
    this.referencedColumn = 'id',
    this.isOwning = false,
    this.cascadeDelete = false,
    this.lazyLoad = true,
    this.eagerLoad = false,
    this.nullable = true,
    this.unique = true,
    this.onDelete = RelationAction.noAction,
    this.onUpdate = RelationAction.noAction,
  });
}

/// OneToMany relationship annotation
///
/// Defines a one-to-many relationship between entities.
/// This is the owning side - a FK column will be created in the target entity's table.
/// The FK column name is automatically derived as {ownerTableName}_id (singular, snake_case).
/// The target table name is automatically resolved from the target entity's @Entity annotation.
///
/// Example:
/// ```dart
/// // In UserEntity (tableName: 'users') - owns the relationship
/// // Automatically creates user_id FK column in posts table (resolved from PostEntity's @Entity)
/// @OneToMany(targetEntity: PostEntity)
/// List<PostEntity>? posts;
///
/// // With explicit FK (if target entity uses a different FK column name):
/// @OneToMany(
///   targetEntity: PurchasesEntity,
/// )
/// List<PurchasesEntity>? purchases;
/// ```
class OneToMany {
  /// The target entity type for this relationship
  final Type targetEntity;

  /// Whether to cascade delete operations
  final bool cascadeDelete;

  /// Whether to lazy load the relationship
  final bool lazyLoad;

  /// Whether to eager load the relationship
  final bool eagerLoad;

  /// Action to take on delete of this entity
  final RelationAction onDelete;

  /// Action to take on update of this entity
  final RelationAction onUpdate;

  const OneToMany({
    required this.targetEntity,
    this.cascadeDelete = false,
    this.lazyLoad = true,
    this.eagerLoad = false,
    this.onDelete = RelationAction.noAction,
    this.onUpdate = RelationAction.noAction,
  });
}

/// ManyToOne relationship annotation
///
/// Defines a many-to-one relationship between entities.
/// Use this on the "many" side - this entity will have the foreign key column.
///
/// Example:
/// ```dart
/// // In PostEntity (the "many" side - has FK column)
/// @ManyToOne(
///   targetEntity: UserEntity,
///   foreignKey: 'author_id',  // FK column name in this table
///   referencedColumn: 'id',   // Referenced column in UserEntity
/// )
/// UserEntity? author;
/// ```
class ManyToOne {
  /// The target entity type for this relationship
  final Type targetEntity;

  /// Foreign key column name in this entity's table
  /// If not provided, defaults to {targetEntity}_id in snake_case
  final String? foreignKey;

  /// Referenced column in the target entity (usually 'id')
  final String referencedColumn;

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

  const ManyToOne({
    required this.targetEntity,
    this.foreignKey,
    this.referencedColumn = 'id',
    this.cascadeDelete = false,
    this.lazyLoad = true,
    this.eagerLoad = false,
    this.nullable = true,
    this.onDelete = RelationAction.noAction,
    this.onUpdate = RelationAction.noAction,
  });
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

  /// Extra columns to add to the junction table
  /// Use this to add custom attributes like timestamps, status flags, etc.
  final List<JunctionColumn>? extraColumns;

  const JoinTable({
    required this.name,
    required this.joinColumn,
    required this.inverseJoinColumn,
    this.additionalIndexes,
    this.extraColumns,
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

/// Custom column for junction tables
///
/// Use this to add extra attributes to ManyToMany junction tables.
///
/// Example:
/// ```dart
/// @ManyToMany(
///   targetEntity: RoleEntity,
///   joinTable: JoinTable(
///     name: 'user_roles',
///     joinColumn: JoinColumn(name: 'user_id'),
///     inverseJoinColumn: JoinColumn(name: 'role_id'),
///     extraColumns: [
///       JunctionColumn(name: 'assigned_at', type: JunctionColumnType.timestamp, defaultValue: 'CURRENT_TIMESTAMP'),
///       JunctionColumn(name: 'assigned_by', type: JunctionColumnType.integer, nullable: true),
///       JunctionColumn(name: 'is_active', type: JunctionColumnType.boolean, defaultValue: 'true'),
///     ],
///   ),
/// )
/// List<RoleEntity>? roles;
/// ```
class JunctionColumn {
  /// Column name
  final String name;

  /// Column type
  final JunctionColumnType type;

  /// Whether this column is nullable
  final bool nullable;

  /// Default value (SQL expression as string)
  final String? defaultValue;

  /// Whether this column should be unique
  final bool unique;

  const JunctionColumn({
    required this.name,
    required this.type,
    this.nullable = false,
    this.defaultValue,
    this.unique = false,
  });
}

/// Column types for junction table extra columns
enum JunctionColumnType {
  integer,
  bigint,
  text,
  varchar,
  boolean,
  real,
  doublePrecision,
  timestamp,
  timestamptz,
  date,
  time,
  json,
  jsonb,
  uuid,
}
