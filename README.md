# DORM - Dart Object-Relational Mapping

A powerful ORM for Dart inspired by Hibernate (Java) and Entity Framework (C#) with LINQ-style query syntax and code generation.

## Features

✨ **Multi-Database Support**

- PostgreSQL (fully implemented)
- MySQL (structure ready)
- SQLite (structure ready)

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

## Quick Start

### 1. Define Your Entities

```dart
// lib/src/models/user_entity.dart
import 'package:dorm/dorm.dart';

part 'user_entity.orm.g.dart';

@Entity(tableName: 'users', dbType: DatabaseType.postgresql)
class UserEntity {
  @Id()
  int? id;

  String name;
  String email;

  UserEntity({this.id, required this.name, required this.email});
}
```

### 2. Define Your Database

```dart
// lib/src/db.dart
import 'package:dorm/dorm.dart';
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

## Annotations

### `@Entity`

Marks a class as a database entity.

```dart
@Entity(
  tableName: 'users',           // Table name (optional, defaults to snake_case of class name)
  dbType: DatabaseType.postgresql,  // Database type
)
class UserEntity { ... }
```

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
)
class Database {
  DatabaseConnection? _connection;
  DatabaseConnection? get connection => _connection;
}
```

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

Marks a field as the primary key.

```dart
@Id()
int? id;
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

### Relationship Annotations

```dart
@OneToMany(mappedBy: 'userId')
List<PostEntity>? posts;

@ManyToOne(foreignKey: 'user_id')
UserEntity? user;

@ManyToMany(joinTable: 'user_roles')
List<RoleEntity>? roles;
```

---

## Migrations

### Creating a Migration

```dart
class Migration001 extends DatabaseMigration {
  @override
  int get version => 1;

  @override
  String get description => 'Create users table';

  @override
  Future<void> up() async {
    await connection.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        email VARCHAR(255) NOT NULL UNIQUE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');
  }

  @override
  Future<void> down() async {
    await connection.execute('DROP TABLE IF EXISTS users');
  }
}
```

### Running Migrations

```dart
await db.initializeDatabase(
  migrations: [
    Migration001(),
    Migration002(),
    Migration003(),
  ],
  validateSchema: true,
);
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

---

## Generated Code

### Repository Extension

The `@Db` annotation generates repository access as an extension:

```dart
// Generated: db.db.g.dart
extension DatabaseRepositories on Database {
  UserEntityRepository get userEntityRepository { ... }
  PostEntityRepository get postEntityRepository { ... }
}
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

## Database Support Status

| Database   | Status               | Package Required   | Notes            |
| ---------- | -------------------- | ------------------ | ---------------- |
| PostgreSQL | ✅ Fully Implemented | `postgres: ^3.1.0` | Production ready |
| SQLite3    | ✅ Fully Implemented | `sqlite3: ^3.0.1`  | Production ready |
| MySQL      | 🔧 Structure Ready   | TBD                | Coming soon      |

---

## Project Structure

```
lib/
├── dorm.dart                 # Main library export
├── src/
│   ├── annotation.dart       # @Entity, @Db, @Column, etc.
│   ├── repository.dart       # Base Repository class
│   ├── query_builder.dart    # LINQ-style query builder
│   ├── migration.dart        # DatabaseMigration & MigrationRunner
│   ├── schema.dart           # DatabaseSchema, ColumnSchema
│   └── database/
│       ├── database_connection.dart
│       ├── database_factory.dart
│       ├── postgresql_connection.dart
│       ├── mysql_connection.dart
│       └── sqlite_connection.dart
└── tool/
    ├── entity_generator.dart # Generates .orm.g.dart
    └── db_generator.dart     # Generates .db.g.dart
```

---

## Examples

See the `/examples` folder for complete working examples:

- `db_postgres_dorm_example/` - PostgreSQL example with entities and database

---

## License

MIT
