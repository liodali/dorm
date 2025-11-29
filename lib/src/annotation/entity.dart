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

/// Primary key annotation for composite primary keys
///
/// Use this on the entity class to define a composite primary key.
/// The columns must exist as fields in the entity.
///
/// Example:
/// ```dart
/// @Entity(tableName: 'order_items')
/// @PrimaryKey(columns: ['order_id', 'product_id'])
/// class OrderItemEntity {
///   int orderId;
///   int productId;
///   int quantity;
/// }
/// ```
class PrimaryKey {
  /// List of column names that form the composite primary key
  final List<String> columns;

  /// Optional name for the primary key constraint
  final String? name;

  const PrimaryKey({required this.columns, this.name});
}

/// Unique constraint annotation for single or multiple columns
///
/// Can be used on a field for single-column unique constraint,
/// or on the entity class for composite unique constraints.
///
/// Example:
/// ```dart
/// // Single column unique
/// @Unique()
/// String email;
///
/// // Composite unique on entity class
/// @Entity(tableName: 'user_roles')
/// @Unique(columns: ['user_id', 'role_id'], name: 'uq_user_role')
/// class UserRoleEntity { ... }
/// ```
class Unique {
  /// List of column names for composite unique constraint
  /// Leave empty when used on a single field
  final List<String>? columns;

  /// Optional name for the unique constraint
  final String? name;

  const Unique({this.columns, this.name});
}

/// Foreign key constraint annotation for defining foreign key constraints
///
/// The column and referenced table/column must exist.
///
/// Example:
/// ```dart
/// @ForeignKeyConstraint(
///   column: 'user_id',
///   referencedTable: 'users',
///   referencedColumn: 'id',
///   onDelete: ConstraintAction.cascade,
/// )
/// int? userId;
/// ```
class ForeignKeyConstraint {
  /// Column name in this table (defaults to field name if on a field)
  final String? column;

  /// Referenced table name
  final String referencedTable;

  /// Referenced column name (usually 'id')
  final String referencedColumn;

  /// Action on delete of referenced row
  final ConstraintAction onDelete;

  /// Action on update of referenced row
  final ConstraintAction onUpdate;

  /// Optional constraint name
  final String? name;

  const ForeignKeyConstraint({
    this.column,
    required this.referencedTable,
    this.referencedColumn = 'id',
    this.onDelete = ConstraintAction.noAction,
    this.onUpdate = ConstraintAction.noAction,
    this.name,
  });
}

/// Actions for constraint operations (foreign key, etc.)
enum ConstraintAction {
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

/// Check constraint annotation
///
/// Example:
/// ```dart
/// @Check(expression: 'age >= 0 AND age <= 150')
/// int age;
/// ```
class Check {
  /// SQL expression for the check constraint
  final String expression;

  /// Optional constraint name
  final String? name;

  const Check({required this.expression, this.name});
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
