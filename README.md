# DORM - Dart Object-Relational Mapping

A powerful ORM for Dart inspired by Hibernate (Java) and Entity Framework (C#) with LINQ-style query syntax and code generation.

## Features

✨ **Multi-Database Support**

- PostgreSQL (fully implemented)
- SQLite (fully implemented)
- MySQL (structure ready)

🔥 **LINQ-Style Queries**

- Fluent query builder API
- Type-safe operations
- Method chaining

🎯 **Entity Framework Patterns**

- Repository pattern with code generation
- Singleton repositories
- Transactions
- Connection pooling

🚀 **Advanced Features**

- Raw SQL queries
- Stored procedures
- Automatic code generation
- Database migrations
- Schema validation & change detection

---

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Configuration File](#configuration-file)
- [Analyzer Plugin](#analyzer-plugin)
- [Public API Reference](#public-api-reference)
  - [Annotations](#annotations)
  - [Repository](#repository-api)
  - [QueryBuilder](#querybuilder-api)
  - [DatabaseConnection](#databaseconnection-api)
  - [Schema](#schema-api)
  - [Migrations](#migrations-api)
  - [Raw Queries & Stored Procedures](#raw-queries--stored-procedures)
- [Database Support](#database-support-status)
- [Examples](#examples)

---

## Installation

Add DORM to your `pubspec.yaml`:

```yaml
dependencies:
  dormql: ^0.3.0
  postgres: ^3.1.0 # For PostgreSQL
  sqlite3: ^3.0.1 # For SQLite

dev_dependencies:
  build_runner: ^2.10.3
  dormql_analyzer_plugin: ^0.1.0 # Optional: Static analysis
```

---

## Quick Start

### 1. Define Your Entities

```dart
// lib/src/models/user_entity.dart
import 'package:dormql/dorm.dart';

part 'user_entity.orm.g.dart';

@Entity(tableName: 'users')
class UserEntity {
  @Id.postgres()  // Use database-specific ID strategy
  int? id;  // ID must be nullable for auto-generated values

  String name;
  String email;

  UserEntity({this.id, required this.name, required this.email});
}
```

**Note:** The database type is now determined from the `@Db` annotation's `DbConfig`, not from the entity. Use `@Id.postgres()`, `@Id.mysql()`, `@Id.sqlite()`, or `@Id.uuid()` for database-specific ID strategies.

### 2. Define Your Database

```dart
// lib/src/db.dart
import 'package:dormql/dorm.dart';
import 'models/user_entity.dart';

part 'db.db.g.dart';

@Db(
  entities: [UserEntity],
  migrationVersion: 1,
  config: DbConfig.postgresql(
    host: 'localhost',
    port: 5432,
    database: 'mydb',
    username: 'user',
    password: 'password',
  ),
  name: 'mydb',
)
class Database {
  /// Connection is managed by generated code
  DatabaseConnection? _connection;
  DatabaseConnection? get connection => _connection;
}
```

The generator creates `setup()`, `init()`, `close()`, and schema methods automatically!

### 3. Generate Code

```bash
dart run build_runner build
```

### 4. Use Your Database

```dart
void main() async {
  final db = Database();
  await db.init();

  // Initialize with migrations and schema validation
  await db.initializeDatabase(
    migrations: [Migration001()],
    validateSchema: true,
  );

  // Access repositories (singleton, auto-initialized)
  final users = await db.userEntityRepository.getAll();

  // LINQ-style queries
  final activeUsers = await db.userEntityRepository
      .query()
      .where('email LIKE @pattern', {'pattern': '%@example.com'})
      .orderByDescending('created_at')
      .take(10)
      .toList();

  await db.close();
}
```

---

## Configuration File

DORM supports loading database configuration from YAML or TOML files, with environment-based configuration and environment variable expansion.

### Quick Setup

1. Create a `db_configuration.yml` file in your project root:

```yaml
environments:
  development:
    type: postgresql
    host: localhost
    port: 5432
    database: myapp_dev
    username: postgres
    password: secret

  production:
    type: postgresql
    host: ${DB_HOST}
    port: 5432
    database: ${DB_NAME}
    username: ${DB_USER}
    password: ${DB_PASSWORD}
    useSSL: true

  test:
    type: sqlite
    filePath: ":memory:"
```

2. Use the `environment` parameter in `setup()`:

```dart
void main() async {
  final db = Database();

  // Option 1: Use environment parameter (recommended)
  await db.setup(environment: 'development');

  // Option 2: Use environment with custom config path
  await db.setup(
    environment: 'production',
    configPath: 'config/database.yml',
  );

  // Option 3: Use DatabaseConfig directly (existing method)
  await db.setup(
    config: DatabaseConfig.postgresql(
      host: 'localhost',
      port: 5432,
      database: 'mydb',
      username: 'user',
      password: 'pass',
    ),
  );
}
```

### Configuration Priority

The `setup()` method resolves configuration in this order (first non-null wins):

1. `config` - Explicit `DatabaseConfig` object
2. `environment` + `configPath` - Load from YAML/TOML configuration file
3. Default config from `@Db` annotation (if provided)

### File Locations

The loader automatically searches for configuration files in these locations:

1. Project root: `db_configuration.yml`, `db_configuration.yaml`, `db_configuration.toml`
2. `config/` directory
3. `lib/` directory

### Environment Variables

Use `${VAR_NAME}` syntax to reference environment variables:

```yaml
environments:
  production:
    host: ${DB_HOST}
    password: ${DB_PASSWORD}
```

### Supported Database Types

| Type       | Aliases                        |
| ---------- | ------------------------------ |
| PostgreSQL | `postgresql`, `postgres`, `pg` |
| MySQL      | `mysql`, `mariadb`             |
| SQLite     | `sqlite`, `sqlite3`            |

### Configuration Options

| Option                     | Type   | Required | Default | Description        |
| -------------------------- | ------ | -------- | ------- | ------------------ |
| `type`                     | string | Yes      | -       | Database type      |
| `host`                     | string | No\*     | -       | Database host      |
| `port`                     | int    | No\*     | -       | Database port      |
| `database`                 | string | No\*     | -       | Database name      |
| `username`                 | string | No\*     | -       | Database username  |
| `password`                 | string | No\*     | -       | Database password  |
| `filePath`                 | string | No\*\*   | -       | SQLite file path   |
| `useSSL`                   | bool   | No       | `false` | Enable SSL         |
| `maxConnections`           | int    | No       | `10`    | Max pool size      |
| `connectionTimeoutSeconds` | int    | No       | `30`    | Timeout in seconds |

\* Required for PostgreSQL and MySQL | \*\* Required for SQLite

### Manual Loading

You can also load configuration manually using `DatabaseConfigLoader`:

```dart
// Auto-detect config file
final loader = DatabaseConfigLoader();
final config = loader.load('development');

// With explicit path
final loader = DatabaseConfigLoader(configPath: 'config/db.yml');
final config = loader.load('production');

// Check available environments
final envs = loader.getAvailableEnvironments(); // ['development', 'production', 'test']
```

For full documentation, see [`docs/DATABASE_CONFIG_FILE.md`](docs/DATABASE_CONFIG_FILE.md).

---

## Type-Safe Column References

DORM v0.4.0 introduces type-safe column references that replace string-based column selection with compile-time validated `ColumnMetadata` objects.

### Usage

```dart
// Type-safe column selection
final users = await userRepo.query()
  .selectColumns([
    UserEntity.columns.id,
    UserEntity.columns.name,
    UserEntity.columns.email,
  ])
  .where('age > @age', {'age': 18})
  .toList();

// Access column metadata
final idColumn = UserEntity.columns.id;
print(idColumn.fieldName);    // 'id'
print(idColumn.columnName);   // 'id'
print(idColumn.dartType);     // 'int?'
print(idColumn.sqlType);      // 'INTEGER'
print(idColumn.isPrimaryKey); // true
```

### Benefits

- **Compile-time type safety** - IDE catches typos before runtime
- **IDE autocomplete support** - Full autocomplete for all column names
- **No string typos** - Column names are verified at compile time
- **Refactoring-friendly** - Renaming fields updates all references automatically
- **Backward compatible** - Old string syntax still works

### ColumnMetadata Properties

```dart
class ColumnMetadata {
  String fieldName;        // Dart field name (e.g., 'firstName')
  String columnName;       // SQL column name (e.g., 'first_name')
  String dartType;         // Dart type (e.g., 'String', 'int?')
  String sqlType;          // SQL type (e.g., 'TEXT', 'INTEGER')
  bool isPrimaryKey;
  bool isNullable;
  String tableName;
}
```

---

## Automatic DTO Generation

DORM automatically generates Data Transfer Objects (DTOs) for all entities. DTOs exclude relationship fields by default, making them perfect for API responses and data transfer.

### Setup

Add the DTO part directive to your entity file:

```dart
import 'package:dormql/dorm.dart';

part 'user_entity.orm.g.dart';
part 'user_entity.dto.g.dart';  // Add this

@Entity(tableName: 'users')
class UserEntity {
  @Id.postgres()
  int? id;
  String name;
  String email;
  String? address;
  String? phoneNumber;

  @OneToMany(targetEntity: PostEntity)
  List<PostEntity>? posts;  // Excluded from DTO

  UserEntity({
    this.id,
    required this.name,
    required this.email,
    this.address,
    this.phoneNumber,
  });
}
```

### Generated DTO Features

The DTO class is automatically generated with these methods:

- **`fromEntity()`** - Create DTO from entity instance
- **`toEntity()`** - Convert DTO back to entity
- **`copyWith()`** - Create modified copy with optional fields
- **`toJson()`** / **`fromJson()`** - JSON serialization
- **Proper `==`, `hashCode`, `toString()`** - Value semantics

### Usage Examples

```dart
// Create DTO from entity
final user = await userRepo.findById(1);
final userDto = UserEntityDto.fromEntity(user!);

// JSON serialization (relationships excluded)
final json = userDto.toJson();
// Output: {'id': 1, 'name': 'John', 'email': 'john@example.com', ...}

// Receive DTO from API
final receivedDto = UserEntityDto.fromJson(jsonData);

// Immutable updates
final updatedDto = userDto.copyWith(name: 'Jane');

// Convert back to entity
final modifiedEntity = updatedDto.toEntity();
await userRepo.save(modifiedEntity);
```

### What's Included in DTO

- ✅ **Primitive fields** - int, String, bool, DateTime, double, etc.
- ❌ **Relationship fields** - @OneToMany, @ManyToOne, @OneToOne, @ManyToMany
- ❌ **@Ignore fields** - Fields marked with @Ignore annotation

### Complete DTO Example

For the UserEntity above, DORM generates:

```dart
class UserEntityDto {
  final int? id;
  final String name;
  final String email;
  final String? address;
  final String? phoneNumber;

  const UserEntityDto({
    this.id,
    required this.name,
    required this.email,
    this.address,
    this.phoneNumber,
  });

  factory UserEntityDto.fromEntity(UserEntity entity) {
    return UserEntityDto(
      id: entity.id,
      name: entity.name,
      email: entity.email,
      address: entity.address,
      phoneNumber: entity.phoneNumber,
    );
  }

  UserEntity toEntity() {
    return UserEntity(
      id: id,
      name: name,
      email: email,
      address: address,
      phoneNumber: phoneNumber,
    );
  }

  UserEntityDto copyWith({
    int? id,
    String? name,
    String? email,
    String? address,
    String? phoneNumber,
  }) {
    return UserEntityDto(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      address: address ?? this.address,
      phoneNumber: phoneNumber ?? this.phoneNumber,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'address': address,
    'phoneNumber': phoneNumber,
  };

  factory UserEntityDto.fromJson(Map<String, dynamic> json) {
    return UserEntityDto(
      id: json['id'] as int?,
      name: json['name'] as String,
      email: json['email'] as String,
      address: json['address'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserEntityDto &&
        other.id == id &&
        other.name == name &&
        other.email == email &&
        other.address == address &&
        other.phoneNumber == phoneNumber;
  }

  @override
  int get hashCode => Object.hash(id, name, email, address, phoneNumber);

  @override
  String toString() =>
    'UserEntityDto(id: $id, name: $name, email: $email, address: $address, phoneNumber: $phoneNumber)';
}
```

---

## Analyzer Plugin

DORM includes a static analysis plugin (`dormql_analyzer_plugin`) that validates your entity configurations at development time, catching errors before runtime.

### Installation

Add to your `analysis_options.yaml`:

```yaml
analyzer:
  plugins:
    - dormql_analyzer_plugin
```

Add to `pubspec.yaml`:

```yaml
dev_dependencies:
  dormql_analyzer_plugin: ^1.0.0
```

### Validation Rules

| Category        | Rule                                 | Description                                       |
| --------------- | ------------------------------------ | ------------------------------------------------- |
| **Entity**      | `dormql_missing_id`                  | Every `@Entity` must have `@Id` or `@PrimaryKey`  |
| **Entity**      | `dormql_multiple_ids`                | Only one `@Id` annotation allowed per entity      |
| **ID Type**     | `dormql_uuid_requires_string`        | UUID strategy requires `String` type              |
| **ID Type**     | `dormql_autoincrement_requires_int`  | AutoIncrement requires `int` or `BigInt`          |
| **ID Nullable** | `dormql_id_nullable_not_allowed`     | ID cannot be nullable with `autoIncrement: false` |
| **Conflict**    | `dormql_id_primarykey_conflict`      | Cannot use both `@Id` and `@PrimaryKey`           |
| **@OneToOne**   | `dormql_onetoone_missing_target`     | Must specify `targetEntity`                       |
| **@OneToOne**   | `dormql_onetoone_mappedby_not_found` | `mappedBy` field must exist in target             |

### Quick Fixes

The plugin provides IDE quick fixes:

- **Missing ID**: Add `@Id() int id;` or `@Id.uuid() String id;`
- **Nullable ID**: Remove `?` from type declaration

For full documentation, see [`packages/dormql_analyzer_plugin/README.md`](packages/dormql_analyzer_plugin/README.md).

---

## Public API Reference

---

## Annotations

### `@Entity`

Marks a class as a database entity.

```dart
@Entity(
  tableName: 'users',           // Table name (optional, defaults to snake_case of class name)
)
class UserEntity { ... }
```

**Note:** Database type is now determined from the `@Db` annotation's `DbConfig`. Use `@Id` with database-specific strategies (`@Id.postgres()`, `@Id.mysql()`, etc.) to control ID generation per database.

### `@Db`

Marks a class as a database definition.

```dart
@Db(
  entities: [UserEntity, PostEntity],  // List of entity types
  migrationVersion: 1,                  // Current migration version
  config: DbConfig.postgresql(          // Database configuration (optional)
    host: 'localhost',
    port: 5432,
    database: 'mydb',
    username: 'user',
    password: 'password',
  ),
  name: 'mydb',                         // Database name (optional)
  generateSql: true,                    // Generate SQL file (optional)
  sqlDialect: DatabaseType.postgresql,  // SQL dialect (optional, defaults to config.dbType)
)
class Database {
  DatabaseConnection? _connection;
  DatabaseConnection? get connection => _connection;
}
```

**Parameters:**

- `entities` - List of entity types to include
- `migrationVersion` - Current migration version for schema tracking
- `config` - Database connection configuration (optional)
- `name` - Database name (optional)
- `generateSql` - When `true`, generates SQL file at `.dart_tool/dorm/<db_name>.sql`
- `sqlDialect` - Target SQL dialect for file generation (defaults to `config.dbType`)

### `DbConfig`

Database configuration for the `@Db` annotation.

```dart
// PostgreSQL
DbConfig.postgresql(host: 'localhost', port: 5432, database: 'mydb', username: 'user', password: 'pass')

// MySQL
DbConfig.mysql(host: 'localhost', port: 3306, database: 'mydb', username: 'root', password: 'pass')

// SQLite
DbConfig.sqlite(database: '/path/to/db.sqlite')
```

### `@Id`

Marks a field as the primary key with optional ID strategy configuration.

#### Basic Usage

```dart
@Id()
int? id;
```

#### ID Strategies

The `@Id` annotation supports different ID generation strategies via the `IDStrategy` enum. Each strategy is optimized for specific database types and field types.

**Strategy Types:**

| Strategy         | Type             | Databases         | Description                        |
| ---------------- | ---------------- | ----------------- | ---------------------------------- |
| `SERIAL`         | `int` / `BigInt` | PostgreSQL        | Auto-incrementing integer (SERIAL) |
| `AUTO_INCREMENT` | `int` / `BigInt` | MySQL, PostgreSQL | Auto-incrementing integer          |
| `AUTOINCREMENT`  | `int` / `BigInt` | SQLite            | Auto-incrementing integer          |
| `UUID`           | `String`         | All               | UUID-based primary key             |

#### Named Constructors (Database-Specific)

```dart
// PostgreSQL - uses SERIAL
@Id.postgres()
int id;

// MySQL - uses AUTO_INCREMENT
@Id.mysql()
int id;

// SQLite - uses AUTOINCREMENT
@Id.sqlite()
int id;

// UUID strategy - works with all databases
@Id.uuid()
String id;
```

#### Default Constructor with Strategy Parameter

```dart
@Id(strategy: IDStrategy.serial)
int id;

@Id(strategy: IDStrategy.uuid)
String id;
```

#### Type Restrictions

The generator enforces type safety at build time:

- **UUID strategy**: Only works with `String` type

  ```dart
  @Id.uuid()
  String? id;  // ✓ Valid (nullable)

  @Id.uuid()
  int id;  // ✗ Build error: UUID strategy can only be used with String type
  ```

- **AutoIncrement strategies**: Only work with `int` or `BigInt` types

  ```dart
  @Id.postgres()
  int? id;  // ✓ Valid (nullable)

  @Id.postgres()
  String id;  // ✗ Build error: AutoIncrement strategy can only be used with int or BigInt
  ```

#### Nullability Requirements

ID fields **must be nullable** by default, unless you explicitly set `autoIncrement: false` and use a non-UUID strategy:

```dart
// ✓ Valid - nullable ID (recommended for auto-generated IDs)
@Id.postgres()
int? id;

// ✓ Valid - nullable UUID
@Id.uuid()
String? id;

// ✓ Valid - non-nullable ID with manual assignment (autoIncrement: false, non-UUID)
@Id(autoIncrement: false, strategy: IDStrategy.serial)
int id;  // Only allowed when autoIncrement is false

// ✗ Build error - non-nullable with auto-generated ID
@Id.postgres()
int id;  // Error: ID field must be nullable unless autoIncrement is false

// ✗ Build error - non-nullable UUID
@Id.uuid()
String id;  // Error: ID field must be nullable
```

**Rationale:** Auto-generated IDs (auto-increment, UUID) are assigned by the database after insertion, so the field must be nullable to represent the "not yet assigned" state before insertion.

#### Database-Specific SQL Generation

The generator automatically produces the correct SQL for each database:

**PostgreSQL:**

```sql
id SERIAL PRIMARY KEY              -- int with SERIAL
id BIGSERIAL PRIMARY KEY           -- BigInt with SERIAL
id UUID DEFAULT gen_random_uuid()  -- String with UUID
```

**MySQL:**

```sql
id INT AUTO_INCREMENT PRIMARY KEY       -- int with AUTO_INCREMENT
id BIGINT AUTO_INCREMENT PRIMARY KEY    -- BigInt with AUTO_INCREMENT
id CHAR(36) PRIMARY KEY                 -- String with UUID
```

**SQLite:**

```sql
id INTEGER PRIMARY KEY AUTOINCREMENT  -- int with AUTOINCREMENT
id TEXT PRIMARY KEY                   -- String with UUID
```

#### Complete Example

```dart
@Entity(tableName: 'users')
class UserEntity {
  @Id.postgres()  // or @Id.mysql(), @Id.sqlite(), @Id.uuid()
  int id;

  String name;
  String email;

  UserEntity({required this.id, required this.name, required this.email});
}
```

### `@Column`

Customizes column mapping.

```dart
@Column(name: 'user_email', type: ColumnType.varchar, length: 255)
String email;
```

### `@Ignore`

Excludes a field from database mapping.

```dart
@Ignore()
String temporaryData;
```

### `@PrimaryKey`

Defines a composite primary key (use on entity class).

```dart
@Entity(tableName: 'order_items')
@PrimaryKey(columns: ['order_id', 'product_id'])
class OrderItemEntity {
  int orderId;
  int productId;
  int quantity;
}
```

**Validation:** The generator will fail if any column in `columns` does not exist as a field in the entity.

**Note:** Cannot use both `@Id` and `@PrimaryKey` on the same entity. Use `@Id` for single-field primary keys and `@PrimaryKey` for composite keys.

#### ID Strategy Validation

The generator enforces type safety for ID strategies at build time:

**Valid Configurations:**

```dart
// ✓ UUID with String (nullable)
@Id.uuid()
String? id;

// ✓ AutoIncrement with int (nullable)
@Id.postgres()
int? id;

// ✓ AutoIncrement with BigInt (nullable)
@Id.mysql()
BigInt? id;

// ✓ Non-nullable ID with manual assignment
@Id(autoIncrement: false, strategy: IDStrategy.serial)
int id;
```

**Invalid Configurations (Build Errors):**

```dart
// ✗ UUID with int - Build error
@Id.uuid()
int? id;  // Error: UUID strategy can only be used with String type

// ✗ AutoIncrement with String - Build error
@Id.postgres()
String? id;  // Error: AutoIncrement strategy can only be used with int or BigInt

// ✗ Non-nullable with auto-generated ID - Build error
@Id.postgres()
int id;  // Error: ID field must be nullable unless autoIncrement is false

// ✗ Non-nullable UUID - Build error
@Id.uuid()
String id;  // Error: ID field must be nullable

// ✗ Both @Id and @Column(primaryKey: true) - Build error
@Id()
@Column(primaryKey: true)
int? id;  // Error: Cannot use both @Id and @Column(primaryKey: true)

// ✗ Both @Id and @PrimaryKey - Build error
@Entity()
@PrimaryKey(columns: ['id'])
class User {
  @Id()
  int? id;  // Error: Cannot use both @Id and @PrimaryKey
}
```

### `@Unique`

Defines unique constraints. Can be used on a field or on the entity class for composite unique constraints.

```dart
// Single column unique (on field)
@Unique()
String email;

// Composite unique (on entity class)
@Entity(tableName: 'user_roles')
@Unique(columns: ['user_id', 'role_id'], name: 'uq_user_role')
class UserRoleEntity {
  int userId;
  int roleId;
}
```

**Validation:** The generator will fail if any column in `columns` does not exist as a field in the entity.

### `@ForeignKeyConstraint`

Defines a foreign key constraint on a field.

```dart
@ForeignKeyConstraint(
  referencedTable: 'users',
  referencedColumn: 'id',
  onDelete: ConstraintAction.cascade,
  onUpdate: ConstraintAction.noAction,
)
int? userId;
```

**Parameters:**

- `column` - Column name (defaults to field name)
- `referencedTable` - Referenced table name (required)
- `referencedColumn` - Referenced column (default: 'id')
- `onDelete` / `onUpdate` - Constraint actions (`ConstraintAction.cascade`, etc.)
- `name` - Optional constraint name

### `@Check`

Defines a check constraint on a field.

```dart
@Check(expression: 'age >= 0 AND age <= 150')
int age;
```

### `@Index`

Creates a database index.

```dart
@Entity(tableName: 'users')
@Index(columns: ['email'], unique: true, name: 'idx_users_email')
class UserEntity { ... }
```

**Validation:** The generator will fail if any column in `columns` does not exist as a field in the entity.

### Relationship Annotations

#### `@OneToMany`

Defines one-to-many and many-to-one relationships. Use `isOwning: true` on the side that owns the foreign key column.

```dart
// In UserEntity (the "one" side - inverse, no FK column)
@OneToMany(
  targetEntity: PostEntity,
  mappedBy: 'author',  // Field name in PostEntity
)
List<PostEntity>? posts;

// In PostEntity (the "many" side - owning, has FK column)
@OneToMany(
  targetEntity: UserEntity,
  foreignKey: 'user_id',     // FK column name in posts table
  referencedColumn: 'id',    // Referenced column in users table
  isOwning: true,
  onDelete: RelationAction.cascade,
)
UserEntity? author;
```

**Parameters:**

- `targetEntity` - The related entity type (required)
- `mappedBy` - Field name in target entity (for inverse side)
- `foreignKey` - FK column name (for owning side)
- `referencedColumn` - Referenced column (default: 'id')
- `isOwning` - Whether this side owns the FK (default: false)
- `nullable` - Whether relationship is nullable (default: true)
- `cascadeDelete` - Cascade delete operations (default: false)
- `lazyLoad` / `eagerLoad` - Loading strategy
- `onDelete` / `onUpdate` - FK constraint actions (`RelationAction.cascade`, etc.)

#### `@OneToOne`

Defines a one-to-one relationship between entities. One side owns the FK column.

```dart
// In UserEntity (inverse side - no FK column)
@OneToOne(
  targetEntity: ProfileEntity,
  mappedBy: 'user',  // Field name in ProfileEntity
)
ProfileEntity? profile;

// In ProfileEntity (owning side - has FK column)
@OneToOne(
  targetEntity: UserEntity,
  foreignKey: 'user_id',
  isOwning: true,
  unique: true,  // Ensures 1:1 constraint
  onDelete: RelationAction.cascade,
)
UserEntity? user;
```

**Parameters:**

- `targetEntity` - The related entity type (required)
- `mappedBy` - Field name in target entity (for inverse side)
- `foreignKey` - FK column name (for owning side)
- `referencedColumn` - Referenced column (default: 'id')
- `isOwning` - Whether this side owns the FK (default: false)
- `unique` - Enforce uniqueness on FK column (default: true)
- `nullable` - Whether relationship is nullable (default: true)
- `onDelete` / `onUpdate` - FK constraint actions

**Generated repository methods:**

```dart
// Get the related entity
Future<ProfileEntity?> getProfile(int userId) async { ... }

// Set the related entity (owning side only)
Future<void> setProfile(int userId, int? profileId) async { ... }
```

#### `@ManyToMany`

Creates a junction table to link two entities. One side is the "owning" side (defines the junction table), the other is the "inverse" side (references the owning side).

```dart
// Owning side - defines the junction table
@ManyToMany(
  targetEntity: RoleEntity,
  joinTable: JoinTable(
    name: 'user_roles',
    joinColumn: JoinColumn(name: 'user_id', referencedColumn: 'id'),
    inverseJoinColumn: JoinColumn(name: 'role_id', referencedColumn: 'id'),
  ),
)
List<RoleEntity>? roles;

// Inverse side - references the owning field
@ManyToMany(
  targetEntity: UserEntity,
  mappedBy: 'roles',  // Field name in UserEntity
)
List<UserEntity>? users;
```

**Auto-generated junction table:** If `joinTable` is not specified, the generator creates one automatically:

```dart
// This will auto-generate junction table "users_role_entity"
@ManyToMany(targetEntity: RoleEntity)
List<RoleEntity>? roles;
```

**Validation:** The generator validates that:

- Target entity exists in `@Db` entities list
- `mappedBy` references a valid field in the target entity
- Owning and inverse sides are properly configured

**Complete ManyToMany Example:**

```dart
// ============================================
// product_entity.dart - OWNING SIDE
// ============================================
import 'package:dorm/dorm.dart';

part 'product_entity.orm.g.dart';

@Entity(tableName: 'products', dbType: DatabaseType.postgresql)
class ProductEntity {
  @Id()
  int? id;

  String name;
  double price;

  /// Owning side - defines the junction table
  @ManyToMany(
    targetEntity: UserEntity,
    joinTable: JoinTable(
      name: 'products_users',
      joinColumn: JoinColumn(name: 'products_id', referencedColumn: 'id'),
      inverseJoinColumn: JoinColumn(name: 'users_id', referencedColumn: 'id'),
    ),
  )
  List<UserEntity>? users;

  ProductEntity({this.id, required this.name, required this.price});
}

// ============================================
// user_entity.dart - INVERSE SIDE
// ============================================
import 'package:dorm/dorm.dart';

part 'user_entity.orm.g.dart';

@Entity(tableName: 'users', dbType: DatabaseType.postgresql)
class UserEntity {
  @Id()
  int? id;

  String name;
  String email;

  /// Inverse side - references the owning side field name
  @ManyToMany(targetEntity: ProductEntity, mappedBy: 'users')
  List<ProductEntity>? products;

  UserEntity({this.id, required this.name, required this.email});
}
```

**Generated Repository Methods:**

```dart
// OWNING SIDE (ProductEntityRepository) - Full CRUD operations
await productRepo.getUsers(productId);           // Get all users for a product
await productRepo.addUser(productId, userId);    // Add user to product
await productRepo.removeUser(productId, userId); // Remove user from product
await productRepo.clearUsers(productId);         // Remove all users from product
await productRepo.setUsers(productId, [1, 2]);   // Replace all users

// INVERSE SIDE (UserEntityRepository) - Read-only
await userRepo.getProducts(userId);              // Get all products for a user
```

**Usage Example:**

```dart
void main() async {
  final db = Database();
  await db.init();

  // Create entities
  final product = ProductEntity(name: 'Laptop', price: 999.99);
  final savedProduct = await db.productEntityRepository.save(product);

  final user = UserEntity(name: 'John', email: 'john@example.com');
  final savedUser = await db.userEntityRepository.save(user);

  // Add relationship (from owning side)
  await db.productEntityRepository.addUser(savedProduct.id!, savedUser.id!);

  // Query from either side
  final usersForProduct = await db.productEntityRepository.getUsers(savedProduct.id!);
  final productsForUser = await db.userEntityRepository.getProducts(savedUser.id!);

  print('Users for product: ${usersForProduct.length}');
  print('Products for user: ${productsForUser.length}');

  await db.close();
}
```

---

## Migrations

### Creating a Migration

Migrations now have built-in helper methods that automatically skip operations if the object already exists:

```dart
class Migration001 extends DatabaseMigration {
  @override
  int get version => 1;

  @override
  String get description => 'Create users table';

  @override
  Future<void> up() async {
    // Option 1: Use schema object (recommended)
    await createTable(DatabaseSchema(
      tableName: 'users',
      columns: [
        ColumnSchema(name: 'id', type: 'INTEGER', primaryKey: true),
        ColumnSchema(name: 'name', type: 'VARCHAR(100)', nullable: false),
        ColumnSchema(name: 'email', type: 'VARCHAR(255)', nullable: false, unique: true),
        ColumnSchema(name: 'created_at', type: 'TIMESTAMP', defaultValue: 'CURRENT_TIMESTAMP'),
      ],
      indexes: [
        IndexSchema(name: 'idx_users_email', columns: ['email'], unique: true),
      ],
    ));

    // Option 2: Use raw SQL
    await connection.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        email VARCHAR(255) NOT NULL UNIQUE
      )
    ''');

    // Helper methods (all skip if already exists)
    await createIndex(name: 'idx_users_name', table: 'users', columns: ['name']);
    await addColumn(table: 'users', column: 'bio', type: 'TEXT', nullable: true);
  }

  @override
  Future<void> down() async {
    await dropTable('users');
  }
}
```

### Migration Helper Methods

All helper methods automatically check if the object exists and skip if it does:

| Method        | Signature                                                               | Description                       |
| ------------- | ----------------------------------------------------------------------- | --------------------------------- |
| `createTable` | `Future<void> createTable(DatabaseSchema schema)`                       | Creates table with IF NOT EXISTS  |
| `dropTable`   | `Future<void> dropTable(String tableName)`                              | Drops table with IF EXISTS        |
| `tableExists` | `Future<bool> tableExists(String tableName)`                            | Returns true if table exists      |
| `createIndex` | `Future<void> createIndex({name, table, columns, unique})`              | Creates index, skips if exists    |
| `dropIndex`   | `Future<void> dropIndex(String name)`                                   | Drops index, skips if not exists  |
| `addColumn`   | `Future<void> addColumn({table, column, type, nullable, defaultValue})` | Adds column, skips if exists      |
| `dropColumn`  | `Future<void> dropColumn({table, column})`                              | Drops column, skips if not exists |

### Migration Types

DORM provides several migration types for different use cases:

#### 1. Custom Migration (Extend DatabaseMigration)

```dart
class Migration001 extends DatabaseMigration {
  @override
  int get version => 1;

  @override
  String get description => 'Create users table';

  @override
  Future<void> up() async {
    await createTable(DatabaseSchema(...));
  }

  @override
  Future<void> down() async {
    await dropTable('users');
  }
}
```

#### 2. RawSqlMigration

For simple SQL-based migrations:

```dart
final migration = RawSqlMigration(
  version: 2,
  description: 'Add status column to users',
  upSql: "ALTER TABLE users ADD COLUMN status VARCHAR(50) DEFAULT 'active';",
  downSql: 'ALTER TABLE users DROP COLUMN status;',
);

// Or with multiple statements
final migration = RawSqlMigration(
  version: 3,
  description: 'Add multiple columns',
  upSqlStatements: [
    'ALTER TABLE users ADD COLUMN age INTEGER;',
    'ALTER TABLE users ADD COLUMN phone VARCHAR(20);',
  ],
  downSqlStatements: [
    'ALTER TABLE users DROP COLUMN phone;',
    'ALTER TABLE users DROP COLUMN age;',
  ],
);
```

#### 3. ManualMigration

For migrations with custom logic using callbacks:

```dart
final migration = ManualMigration(
  version: 4,
  description: 'Seed initial data',
  onUp: (connection, schemaManager) async {
    await connection.execute(
      "INSERT INTO users (name, email) VALUES ('Admin', 'admin@example.com')",
    );
  },
  onDown: (connection, schemaManager) async {
    await connection.execute(
      "DELETE FROM users WHERE email = 'admin@example.com'",
    );
  },
);
```

#### 4. CompositeMigration

Combine multiple migrations into one:

```dart
final migration = CompositeMigration(
  version: 5,
  description: 'Add user profile fields',
  steps: [
    RawSqlMigration(
      version: 0, // ignored in composite
      description: 'Add bio column',
      upSql: 'ALTER TABLE users ADD COLUMN bio TEXT;',
      downSql: 'ALTER TABLE users DROP COLUMN bio;',
    ),
    RawSqlMigration(
      version: 0,
      description: 'Add avatar column',
      upSql: 'ALTER TABLE users ADD COLUMN avatar_url VARCHAR(500);',
      downSql: 'ALTER TABLE users DROP COLUMN avatar_url;',
    ),
  ],
);
```

### MigrationRunner

Use `MigrationRunner` to execute migrations:

```dart
final runner = MigrationRunner(connection, [
  Migration001(),
  Migration002(),
  migration3,  // RawSqlMigration
  migration4,  // ManualMigration
]);

// Run all pending migrations
await runner.runMigrations();

// Rollback the last migration
await runner.rollbackLast();

// Run ad-hoc SQL (not tracked)
await runner.runSql('UPDATE users SET status = @status', parameters: {'status': 'active'});

// Run multiple SQL statements (not tracked)
await runner.runSqlStatements([
  'CREATE INDEX idx_users_status ON users(status);',
  'CREATE INDEX idx_users_created ON users(created_at);',
]);

// Run manual callback (not tracked)
await runner.runManual((connection, schemaManager) async {
  // Custom logic
});
```

### Running Migrations

The `setup()` method handles the complete database initialization flow:

```dart
// Complete setup: connect → create schema → run migrations → validate
await db.setup(
  config: DatabaseConfig.postgresql(...),  // Optional if defined in @Db
  migrations: [
    Migration001(),
    Migration002(),
    RawSqlMigration(version: 3, description: '...', upSql: '...'),
  ],
  autoCreateSchema: true,   // Creates tables from schema (default: true)
  validateSchema: true,     // Validates schema matches code (default: true)
);
```

**Flow:**

1. **Connect** - Establishes database connection
2. **Create Schema** - Creates all tables using `IF NOT EXISTS` (skips existing)
3. **Run Migrations** - Executes pending migrations (skips already applied)
4. **Validate Schema** - Checks schema matches code definitions

You can also call individual methods:

```dart
// Just connect
await db.init(config);

// Create schema tables (safe to call multiple times)
await db.createSchema();

// Run migrations only
await db.initializeDatabase(migrations: [...]);

// Get SQL without executing
final sql = db.getCreateSchemaSql();
print(sql.join('\n'));
```

### Schema Validation

DORM automatically:

- Generates a **schema hash** from your entities
- Compares the hash with the stored hash in the database
- **Fails initialization** if schema changed but `migrationVersion` was not bumped

```dart
// If you add a new column to UserEntity but don't bump migrationVersion:
// StateError: Schema has changed but migration version was not bumped!
// Differences found:
// Column "new_column" missing in table "users"
// Please increment migrationVersion in @Db annotation and create a migration.
```

### Migration Best Practices

1. **Always test migrations** on a copy of production data before deploying
2. **Never delete applied migrations** in production
3. **Keep `down()` methods functional** for rollback capability
4. **Use timestamp-based versions** to avoid conflicts in team environments
5. **Bump `migrationVersion`** in `@Db` annotation when schema changes

---

## Schema to SQL

### Accessing Entity Schema

Each entity has a generated schema extension in `.schema.g.dart`:

```dart
// Access schema via extension
final schema = UserEntitySchema.schema;
final tableName = UserEntitySchema.tableName;

// Or from an instance
final user = UserEntity();
// user.schema (if instance method needed)
```

### Converting Schema to SQL

Use the extension methods to convert schema objects to SQL:

```dart
// Get schema from entity
final schema = UserEntitySchema.schema;

// Or create manually
final schema = DatabaseSchema(
  tableName: 'users',
  columns: [
    ColumnSchema(name: 'id', type: 'INTEGER', primaryKey: true),
    ColumnSchema(name: 'name', type: 'VARCHAR(100)', nullable: false),
    ColumnSchema(name: 'email', type: 'VARCHAR(255)', nullable: false, unique: true),
  ],
  foreignKeys: [
    ForeignKey(column: 'role_id', referencedTable: 'roles', referencedColumn: 'id'),
  ],
  indexes: [
    IndexSchema(name: 'idx_users_email', columns: ['email'], unique: true),
  ],
);

// Generate CREATE TABLE SQL with IF NOT EXISTS
final createSql = schema.toCreateTableSql(DatabaseType.postgresql);
// CREATE TABLE IF NOT EXISTS users (
//   id SERIAL PRIMARY KEY,
//   name VARCHAR(100) NOT NULL,
//   email VARCHAR(255) NOT NULL UNIQUE,
//   FOREIGN KEY (role_id) REFERENCES roles (id)
// );

// Generate CREATE INDEX SQL
final indexSql = schema.toCreateIndexSql(DatabaseType.postgresql);
// ['CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users (email);']

// Generate DROP TABLE SQL
final dropSql = schema.toDropTableSql(DatabaseType.postgresql);
// DROP TABLE IF EXISTS users;
```

### SchemaManager

Use `SchemaManager` to execute schema operations:

```dart
final schemaManager = SchemaManager(connection);

// Create table (skips if exists)
await schemaManager.createTable(schema);

// Create multiple tables
await schemaManager.createTables([usersSchema, postsSchema, rolesSchema]);

// Check if table exists
final exists = await schemaManager.tableExists('users');

// Get all table names
final tables = await schemaManager.getTableNames();

// Drop table (skips if not exists)
await schemaManager.dropTable(schema);
```

---

## Generated Code

### SQL File Generation

When `generateSql: true` is set in `@Db`, the generator creates SQL files:

**Location:** `.dart_tool/dorm/`

**Files generated:**

- `<db_name>.sql` - Current schema (overwritten on each build)
- `<db_name>_v<version>.sql` - Versioned copy for each migration version

**Example output:**

```sql
-- ============================================================
-- Database: mydb
-- Generated: 2024-01-15T10:30:00.000Z
-- Migration Version: 1
-- SQL Dialect: postgresql
-- ============================================================

-- Entity Tables
-- ============================================================

-- Table: users
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL
);

-- Table: posts
CREATE TABLE IF NOT EXISTS posts (
  id SERIAL PRIMARY KEY,
  title TEXT NOT NULL,
  user_id INTEGER NOT NULL
);

-- Junction Tables (ManyToMany)
-- ============================================================

-- Junction: users_roles
CREATE TABLE IF NOT EXISTS users_roles (
  users_id INTEGER NOT NULL,
  roles_id INTEGER NOT NULL,
  PRIMARY KEY (users_id, roles_id),
  FOREIGN KEY (users_id) REFERENCES users (id) ON DELETE CASCADE,
  FOREIGN KEY (roles_id) REFERENCES roles (id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_users_roles_users_id ON users_roles (users_id);
CREATE INDEX IF NOT EXISTS idx_users_roles_roles_id ON users_roles (roles_id);
```

### Repository Extension

The `@Db` annotation generates repository access as an extension:

```dart
// Generated: db.db.g.dart
extension DatabaseRepositories on Database {
  UserEntityRepository get userEntityRepository { ... }
  PostEntityRepository get postEntityRepository { ... }
}
```

### ManyToMany Repository Methods

For entities with `@ManyToMany` relationships, the generator creates dedicated methods:

```dart
// Generated: user_entity.orm.g.dart
class UserEntityRepository extends Repository<UserEntity> {
  // ... standard CRUD methods ...

  /// Get all roles for a user
  Future<List<RoleEntity>> getRoles(int userId) async { ... }

  /// Add a role to a user
  Future<void> addRole(int userId, int roleId) async { ... }

  /// Remove a role from a user
  Future<void> removeRole(int userId, int roleId) async { ... }

  /// Clear all roles from a user
  Future<void> clearRoles(int userId) async { ... }

  /// Set roles for a user (replaces all existing)
  Future<void> setRoles(int userId, List<int> roleIds) async { ... }

  /// Find user with related data
  Future<Map<String, dynamic>?> findByIdWithRelations(
    int id, {
    List<String> includes = const ['roles'],
  }) async { ... }

  /// Get all users with related data
  Future<List<Map<String, dynamic>>> getAllWithRelations({
    List<String> includes = const ['roles'],
  }) async { ... }
}
```

**Usage:**

```dart
// Get user with roles
final result = await userRepo.findByIdWithRelations(1, includes: ['roles']);
final user = result!['entity'] as UserEntity;
final roles = result['roles'] as List<RoleEntity>;

// Manage roles
await userRepo.addRole(userId, roleId);
await userRepo.removeRole(userId, roleId);
await userRepo.setRoles(userId, [1, 2, 3]);
```

### Schema Definition

Schema is generated at the database level:

```dart
// Generated: db.db.g.dart
const userEntitySchema = DatabaseSchema(
  tableName: 'users',
  columns: [
    ColumnSchema(name: 'id', type: 'INTEGER', nullable: true, primaryKey: true),
    ColumnSchema(name: 'name', type: 'TEXT', nullable: false, primaryKey: false),
    ColumnSchema(name: 'email', type: 'TEXT', nullable: false, primaryKey: false),
  ],
);

const databaseSchemas = [userEntitySchema, postEntitySchema];
```

### Lifecycle Extension

```dart
// Generated: db.db.g.dart
extension DatabaseLifecycle on Database {
  static const int currentMigrationVersion = 1;
  static const String schemaHash = 'abc123...';

  /// Get all schemas defined in code
  List<DatabaseSchema> get schemas => [...];

  /// One-liner setup: connect + migrate + validate
  Future<void> setup({
    DatabaseConfig? config,  // Uses annotation config if not provided
    List<DatabaseMigration> migrations = const [],
    bool validateSchema = true,
  }) async { ... }

  /// Initialize connection only
  Future<void> init(DatabaseConfig? config) async { ... }

  /// Run migrations and validate schema
  Future<void> initializeDatabase({
    List<DatabaseMigration> migrations = const [],
    bool validateSchema = true,
  }) async { ... }

  /// Retrieve schema from database
  Future<DatabaseSchema?> getSchemaFromDatabase(String tableName) async { ... }
  Future<List<DatabaseSchema>> getAllSchemasFromDatabase() async { ... }

  Future<int> getAppliedMigrationVersion() async { ... }
  Future<bool> hasPendingMigrations(List<DatabaseMigration> migrations) async { ... }

  /// Close connection
  Future<void> close() async { ... }
}
```

---

## Repository API

The `Repository<T>` class provides CRUD operations for entities.

### Constructor Parameters

```dart
Repository(
  String tableName, {
  String primaryKeyColumn = 'id',
  bool autoIncrementPrimaryKey = true,
})
```

### Core Methods

| Method                                   | Return Type       | Description                                           |
| ---------------------------------------- | ----------------- | ----------------------------------------------------- |
| `save(T entity)`                         | `Future<T>`       | Insert entity, returns saved entity with generated ID |
| `findById(dynamic id)`                   | `Future<T?>`      | Find entity by primary key                            |
| `getAll()`                               | `Future<List<T>>` | Get all entities                                      |
| `delete(dynamic id)`                     | `Future<void>`    | Delete by primary key                                 |
| `deleteEntity(T entity)`                 | `Future<void>`    | Delete entity instance                                |
| `query()`                                | `QueryBuilder<T>` | Create LINQ-style query builder                       |
| `setConnection(DatabaseConnection conn)` | `void`            | Set database connection                               |

### Abstract Methods (Implemented by Generated Code)

```dart
/// Convert database row to entity
T fromRow(Map<String, dynamic> row);

/// Convert entity to database row
Map<String, dynamic> toRow(T entity);

/// Load relationships for eager loading
Future<void> loadRelationships(T entity, List<String> includes);
```

### Raw Query Methods

```dart
/// Execute raw SQL query
RawQuery executeRawQuery(String sql, [Map<String, dynamic>? parameters]);

/// Execute stored procedure
StoredProcedure executeProcedure(String name, {List<dynamic>? parameters});
```

---

## QueryBuilder API

The `QueryBuilder<T>` class provides LINQ-style fluent query building.

### Query Methods

| Method                                                    | Description                        |
| --------------------------------------------------------- | ---------------------------------- |
| `select(Function(SelectBuilder) builder)`                 | Select specific columns            |
| `where(String condition, [Map<String, dynamic>? params])` | WHERE clause with parameters       |
| `whereSimple(String column, dynamic value)`               | Simple equality WHERE              |
| `whereIn(String column, List<dynamic> values)`            | WHERE IN clause                    |
| `whereNotIn(String column, List<dynamic> values)`         | WHERE NOT IN clause                |
| `whereBetween(String column, dynamic from, dynamic to)`   | BETWEEN clause                     |
| `whereLike(String column, String pattern)`                | LIKE clause                        |
| `whereILike(String column, String pattern)`               | Case-insensitive LIKE (PostgreSQL) |
| `whereNull(String column)`                                | IS NULL clause                     |
| `whereNotNull(String column)`                             | IS NOT NULL clause                 |

### Join Methods

| Method                                      | Description             |
| ------------------------------------------- | ----------------------- |
| `innerJoin(String table, String condition)` | INNER JOIN              |
| `leftJoin(String table, String condition)`  | LEFT JOIN               |
| `rightJoin(String table, String condition)` | RIGHT JOIN              |
| `include(String relationshipName)`          | Eager load relationship |

### Ordering & Pagination

| Method                             | Description     |
| ---------------------------------- | --------------- |
| `orderBy(String column)`           | ORDER BY ASC    |
| `orderByDescending(String column)` | ORDER BY DESC   |
| `skip(int count)`                  | OFFSET          |
| `take(int count)`                  | LIMIT           |
| `distinct()`                       | SELECT DISTINCT |

### Execution Methods

| Method               | Return Type       | Description                            |
| -------------------- | ----------------- | -------------------------------------- |
| `toList()`           | `Future<List<T>>` | Execute and get all results            |
| `firstOrDefault()`   | `Future<T?>`      | Get first result or null               |
| `first()`            | `Future<T>`       | Get first result (throws if not found) |
| `countSql()`         | `Future<int>`     | Count matching records                 |
| `any()`              | `Future<bool>`    | Check if any records match             |
| `max(String column)` | `Future<num?>`    | Get maximum value                      |
| `min(String column)` | `Future<num?>`    | Get minimum value                      |
| `sum(String column)` | `Future<num?>`    | Get sum of column                      |
| `avg(String column)` | `Future<num?>`    | Get average of column                  |
| `toSql()`            | `String`          | Get generated SQL (for debugging)      |

### SelectBuilder

Used with the `select()` method to specify columns:

```dart
class SelectBuilder {
  void column(String name);
  void columns(List<String> names);
}
```

### Usage Examples

```dart
// Select specific columns
final users = await userRepo
    .query()
    .select((s) => s.columns(['id', 'name', 'email']))
    .toList();

// Complex query with multiple conditions
final users = await userRepo
    .query()
    .where('status = @status', {'status': 'active'})
    .whereNotNull('email')
    .whereLike('name', '%John%')
    .orderByDescending('created_at')
    .skip(10)
    .take(20)
    .toList();

// Aggregations
final totalSales = await orderRepo.query().sum('amount');
final avgPrice = await productRepo.query().avg('price');
final maxAge = await userRepo.query().max('age');

// Check existence
final hasAdmins = await userRepo
    .query()
    .where('role = @role', {'role': 'admin'})
    .any();
```

---

## DatabaseConnection API

The `DatabaseConnection` abstract class defines the interface for all database connections.

### Interface Methods

```dart
abstract class DatabaseConnection {
  /// Execute query and return mapped results
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? parameters,
  });

  /// Execute non-query (INSERT, UPDATE, DELETE)
  Future<int> execute(String sql, {Map<String, dynamic>? parameters});

  /// Execute query and return raw results
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
```

### DatabaseTransaction Interface

```dart
abstract class DatabaseTransaction {
  Future<List<Map<String, dynamic>>> query(String sql, {Map<String, dynamic>? parameters});
  Future<int> execute(String sql, {Map<String, dynamic>? parameters});
  Future<void> commit();
  Future<void> rollback();
}
```

### DatabaseConfig Factory Methods

```dart
// PostgreSQL
DatabaseConfig.postgresql({
  required String host,
  required int port,
  required String database,
  required String username,
  required String password,
  bool useSSL = false,
  int maxConnections = 10,
  Duration connectionTimeout = const Duration(seconds: 30),
})

// MySQL
DatabaseConfig.mysql({
  required String host,
  required int port,
  required String database,
  required String username,
  required String password,
  bool useSSL = false,
  int maxConnections = 10,
  Duration connectionTimeout = const Duration(seconds: 30),
})

// SQLite
DatabaseConfig.sqlite({required String filePath})
```

### DatabaseType Enum

```dart
enum DatabaseType { postgresql, mysql, sqlite }
```

---

## Schema API

### DatabaseSchema

```dart
class DatabaseSchema {
  final String tableName;
  final List<dynamic> columns;
  final List<ForeignKey>? foreignKeys;
  final List<IndexSchema>? indexes;
  final List<String>? primaryKeyColumns;
  final List<UniqueConstraint>? uniqueConstraints;
  final List<CheckConstraint>? checkConstraints;

  const DatabaseSchema({
    required this.tableName,
    required this.columns,
    this.foreignKeys,
    this.indexes,
    this.primaryKeyColumns,
    this.uniqueConstraints,
    this.checkConstraints,
  });
}
```

### ColumnSchema

```dart
class ColumnSchema {
  final String name;
  final String type;
  final bool nullable;
  final bool primaryKey;
  final bool unique;
  final String? defaultValue;
  final bool autoIncrement;

  const ColumnSchema({
    required this.name,
    required this.type,
    this.nullable = true,
    this.primaryKey = false,
    this.unique = false,
    this.defaultValue,
    this.autoIncrement = false,
  });
}
```

### ForeignKey

```dart
class ForeignKey {
  final String column;
  final String referencedTable;
  final String referencedColumn;
  final ForeignKeyAction? onDelete;
  final ForeignKeyAction? onUpdate;
  final String? name;

  const ForeignKey({
    required this.column,
    required this.referencedTable,
    required this.referencedColumn,
    this.onDelete,
    this.onUpdate,
    this.name,
  });
}

enum ForeignKeyAction { cascade, restrict, setNull, setDefault, noAction }
```

### Schema Extension Methods

```dart
extension DatabaseSchemaToSql on DatabaseSchema {
  /// Generate CREATE TABLE SQL
  String toCreateTableSql(DatabaseType dbType);

  /// Generate CREATE INDEX SQL statements
  List<String> toCreateIndexSql(DatabaseType dbType);

  /// Generate DROP TABLE SQL
  String toDropTableSql(DatabaseType dbType);

  /// Generate all SQL statements
  List<String> toAllSql(DatabaseType dbType);
}
```

### SchemaManager

```dart
class SchemaManager {
  SchemaManager(DatabaseConnection connection);

  Future<bool> createTable(DatabaseSchema schema);
  Future<void> createTables(List<DatabaseSchema> schemas);
  Future<void> dropTable(DatabaseSchema schema);
  Future<bool> tableExists(String tableName);
  Future<bool> indexExists(String indexName, String tableName);
  Future<List<String>> getTableNames();
}
```

---

## Migrations API

### DatabaseMigration Abstract Class

```dart
abstract class DatabaseMigration {
  int get version;
  String get description;
  DatabaseType get dbType;

  void setConnection(DatabaseConnection conn);

  /// Migration up - create/modify schema
  Future<void> up();

  /// Migration down - rollback schema
  Future<void> down();

  // Helper methods
  Future<void> createTable(DatabaseSchema schema);
  Future<void> dropTable(String tableName);
  Future<bool> tableExists(String tableName);
  Future<void> createIndex({
    required String name,
    required String table,
    required List<String> columns,
    bool unique = false,
  });
  Future<void> dropIndex(String name);
  Future<void> addColumn({
    required String table,
    required String column,
    required String type,
    bool nullable = true,
    String? defaultValue,
  });
  Future<void> dropColumn({required String table, required String column});
}
```

### MigrationRunner

```dart
class MigrationRunner {
  MigrationRunner(DatabaseConnection connection, List<DatabaseMigration> migrations);

  Future<void> runMigrations();
  Future<void> rollbackLast();
  Future<void> runSql(String sql, {Map<String, dynamic>? parameters});
  Future<void> runSqlStatements(List<String> statements);
  Future<void> runManual(MigrationCallback callback);
}
```

### Migration Types

```dart
// Raw SQL Migration
RawSqlMigration({
  required int version,
  required String description,
  String upSql = '',
  String? downSql,
  List<String>? upSqlStatements,
  List<String>? downSqlStatements,
})

// Manual Migration with Callbacks
ManualMigration({
  required int version,
  required String description,
  required MigrationCallback onUp,
  MigrationCallback? onDown,
})

// Composite Migration
CompositeMigration({
  required int version,
  required String description,
  required List<DatabaseMigration> steps,
})
```

---

## Raw Queries & Stored Procedures

### RawQuery

```dart
class RawQuery {
  RawQuery(DatabaseConnection connection, String sql, [Map<String, dynamic> parameters = const {}]);

  Future<List<Map<String, dynamic>>> execute();
  Future<Map<String, dynamic>?> executeFirstOrDefault();
  Future<dynamic> executeScalar();
  Future<int> executeNonQuery();
  String toSql();  // Get SQL with parameters substituted (for debugging)
}
```

### StoredProcedure

```dart
class StoredProcedure {
  StoredProcedure({
    required String name,
    String schema = 'public',
    List<dynamic> parameters = const [],
    DatabaseConnection? connection,
  });

  void setConnection(DatabaseConnection connection);
  Future<List<Map<String, dynamic>>> execute();
  Future<dynamic> executeScalar();
  Future<void> executeNonQuery();
}
```

### StoredProcedureBuilder

```dart
class StoredProcedureBuilder {
  StoredProcedureBuilder(DatabaseConnection connection, String name);

  StoredProcedureBuilder withSchema(String schema);
  StoredProcedureBuilder addParameter(dynamic value);
  StoredProcedure build();
}
```

### Usage Examples

```dart
// Raw query
final results = await repo.executeRawQuery(
  'SELECT * FROM users WHERE age > @age ORDER BY name',
  {'age': 18},
).execute();

// Stored procedure
final proc = repo.executeProcedure('calculate_total', parameters: [orderId]);
final total = await proc.executeScalar();

// Using builder
final proc = StoredProcedureBuilder(connection, 'get_user_stats')
    .withSchema('reporting')
    .addParameter(userId)
    .addParameter(startDate)
    .build();
final stats = await proc.execute();
```

---

## Database Support Status

| Database   | Status               | Package Required   | Notes            |
| ---------- | -------------------- | ------------------ | ---------------- |
| PostgreSQL | ✅ Fully Implemented | `postgres: ^3.1.0` | Production ready |
| SQLite3    | ✅ Fully Implemented | `sqlite3: ^3.0.1`  | Production ready |
| MySQL      | 🔧 Structure Ready   | `mysql1: ^0.20.0`  | Coming soon      |

---

## Project Structure

```
lib/
├── dorm.dart                 # Main library export
├── src/
│   ├── annotation.dart       # @Entity, @Db, @Column, etc.
│   ├── repository.dart       # Base Repository class
│   ├── query_builder.dart    # LINQ-style query builder
│   ├── raw_query.dart        # Raw SQL query execution
│   ├── stored_procedure.dart # Stored procedure execution
│   ├── migration.dart        # DatabaseMigration & MigrationRunner
│   ├── schema.dart           # DatabaseSchema, ColumnSchema
│   ├── annotation/
│   │   ├── entity.dart       # @Entity, @Column, @Id, @Index, etc.
│   │   ├── relationship.dart # @OneToOne, @OneToMany, @ManyToMany
│   │   ├── database.dart     # @Db, DbConfig
│   │   ├── query.dart        # Query-related annotations
│   │   └── migration.dart    # Migration annotations
│   └── database/
│       ├── database_connection.dart
│       ├── database_factory.dart
│       ├── postgresql_connection.dart
│       ├── mysql_connection.dart
│       └── sqlite_connection.dart
└── tool/
    ├── entity_generator.dart # Generates .orm.g.dart
    ├── db_generator.dart     # Generates .db.g.dart
    └── db_schema_generator.dart # Generates schema SQL
```

---

## Examples

See the `/examples` folder for complete working examples:

- `db_postgres_dorm_example/` - PostgreSQL example with entities and database
- `example/` - Basic usage examples

---

## License

MIT
