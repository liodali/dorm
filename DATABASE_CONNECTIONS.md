# Database Connections Guide

This document explains how to use the different database connections in DORM.

## Overview

DORM provides a unified interface for connecting to multiple database systems:

| Database   | Status               | Package Required   | Notes            |
| ---------- | -------------------- | ------------------ | ---------------- |
| PostgreSQL | ✅ Fully Implemented | `postgres: ^3.1.0` | Production ready |
| SQLite3    | ✅ Fully Implemented | `sqlite3: ^3.0.1`  | Production ready |
| MySQL      | 🔧 Structure Ready   | `mysql1: ^0.20.0`  | Coming soon      |

## Connection Architecture

All database connections implement the `DatabaseConnection` interface:

```dart
abstract class DatabaseConnection {
  /// Execute query and return mapped results as List<Map>
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? parameters,
  });

  /// Execute non-query (INSERT, UPDATE, DELETE) and return affected rows
  Future<int> execute(String sql, {Map<String, dynamic>? parameters});

  /// Execute query and return raw results as List<List>
  Future<List<List<dynamic>>> rawQuery(
    String sql, {
    Map<String, dynamic>? parameters,
  });

  /// Begin a database transaction
  Future<DatabaseTransaction> beginTransaction();

  /// Close the connection
  Future<void> close();

  /// Check if connection is open
  bool get isOpen;

  /// Get the database type
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

### DatabaseType Enum

```dart
enum DatabaseType { postgresql, mysql, sqlite }
```

## DatabaseConfig

Use `DatabaseConfig` to configure database connections:

```dart
class DatabaseConfig {
  final DatabaseType type;
  final String? host;
  final int? port;
  final String? database;
  final String? username;
  final String? password;
  final String? filePath;      // For SQLite
  final bool useSSL;
  final int maxConnections;
  final Duration connectionTimeout;
  final Map<String, dynamic>? additionalParams;
}
```

### Factory Constructors

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

---

## PostgreSQL Connection

### Setup

Add to `pubspec.yaml`:

```yaml
dependencies:
  postgres: ^3.1.0
```

### Usage

```dart
import 'package:dorm/dorm.dart';

// Configure connection
final config = DatabaseConfig.postgresql(
  host: 'localhost',
  port: 5432,
  database: 'mydb',
  username: 'postgres',
  password: 'password',
  useSSL: false,
  connectionTimeout: Duration(seconds: 30),
);

// Create connection
final connection = await DatabaseFactory.createConnection(config);

// Execute queries
final results = await connection.query(
  'SELECT * FROM users WHERE email = @email',
  parameters: {'email': 'user@example.com'},
);

// Transactions
final transaction = await connection.beginTransaction();
try {
  await transaction.execute(
    'INSERT INTO users (name, email) VALUES (@name, @email)',
    parameters: {'name': 'John', 'email': 'john@example.com'},
  );
  await transaction.commit();
} catch (e) {
  await transaction.rollback();
}

// Close connection
await connection.close();
```

### Features

- ✅ Named parameters using `@param` syntax
- ✅ SSL/TLS support
- ✅ Connection timeout configuration
- ✅ Transaction support
- ✅ Connection pooling
- ✅ Prepared statements

## SQLite3 Connection

### Setup

Already included in `pubspec.yaml`:

```yaml
dependencies:
  sqlite3: ^3.0.1
```

### Usage

```dart
import 'package:dorm/dorm.dart';

// Configure connection
final config = DatabaseConfig.sqlite(
  filePath: '/path/to/database.db',
  // Or use in-memory database:
  // filePath: ':memory:',
);

// Create connection
final connection = await DatabaseFactory.createConnection(config);

// Create table
await connection.execute(
  'CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT, email TEXT)',
);

// Insert data
await connection.execute(
  'INSERT INTO users (name, email) VALUES (@name, @email)',
  parameters: {'name': 'Jane', 'email': 'jane@example.com'},
);

// Query data
final results = await connection.query(
  'SELECT * FROM users WHERE name = @name',
  parameters: {'name': 'Jane'},
);

// Transactions
final transaction = await connection.beginTransaction();
try {
  await transaction.execute(
    'UPDATE users SET email = @email WHERE id = @id',
    parameters: {'email': 'newemail@example.com', 'id': 1},
  );
  await transaction.commit();
} catch (e) {
  await transaction.rollback();
}

// Close connection
await connection.close();
```

### Features

- ✅ Named parameters using `@param` syntax (converted to `?` internally)
- ✅ In-memory databases
- ✅ File-based databases
- ✅ Transaction support
- ✅ Fast local storage
- ✅ No server required

## MySQL Connection

### Setup

**Step 1:** Add package to `pubspec.yaml`:

```yaml
dependencies:
  mysql1: ^0.20.0
```

**Step 2:** Run:

```bash
dart pub get
```

**Step 3:** Uncomment the implementation code in `lib/src/database/mysql_connection.dart`:

- Uncomment the import statement
- Uncomment the connection logic in `open()` method
- Uncomment query/execute implementations
- Uncomment transaction implementations

### Usage (After Setup)

```dart
import 'package:dorm/dorm.dart';

// Configure connection
final config = DatabaseConfig.mysql(
  host: 'localhost',
  port: 3306,
  database: 'mydb',
  username: 'root',
  password: 'password',
  useSSL: false,
  connectionTimeout: Duration(seconds: 30),
);

// Create connection
final connection = await DatabaseFactory.createConnection(config);

// Execute queries (same API as PostgreSQL)
final results = await connection.query(
  'SELECT * FROM users WHERE email = @email',
  parameters: {'email': 'user@example.com'},
);

// Close connection
await connection.close();
```

### Features (When Enabled)

- ✅ Named parameters using `@param` syntax (converted to `?` internally)
- ✅ SSL/TLS support
- ✅ Connection timeout configuration
- ✅ Transaction support
- ✅ Connection pooling
- ✅ Prepared statements

## Connection Pooling

All database types support connection pooling for better performance:

```dart
// Create a connection pool
final pool = await DatabaseFactory.createPool(
  config,
  maxConnections: 10,
);

// Get connection from pool
final connection = await pool.getConnection();

try {
  // Use connection
  final results = await connection.query('SELECT * FROM users');
} finally {
  // Release connection back to pool
  await pool.releaseConnection(connection);
}

// Check pool statistics
print(pool.stats); // {available: 9, used: 1, total: 10, max: 10}

// Close pool (closes all connections)
await pool.close();
```

## Parameter Binding

All database connections use named parameters with `@param` syntax:

```dart
// Named parameters
await connection.query(
  'SELECT * FROM users WHERE name = @name AND age > @age',
  parameters: {
    'name': 'John',
    'age': 25,
  },
);

// Multiple parameters
await connection.execute(
  'INSERT INTO users (name, email, age) VALUES (@name, @email, @age)',
  parameters: {
    'name': 'Jane Doe',
    'email': 'jane@example.com',
    'age': 30,
  },
);
```

**Note:** PostgreSQL uses native named parameters. SQLite and MySQL convert `@param` to `?` internally.

## Transactions

All database connections support transactions:

```dart
final transaction = await connection.beginTransaction();

try {
  // Execute multiple operations
  await transaction.execute(
    'INSERT INTO users (name) VALUES (@name)',
    parameters: {'name': 'User 1'},
  );

  await transaction.execute(
    'INSERT INTO posts (user_id, title) VALUES (@userId, @title)',
    parameters: {'userId': 1, 'title': 'First Post'},
  );

  // Commit if all successful
  await transaction.commit();
} catch (e) {
  // Rollback on error
  await transaction.rollback();
  rethrow;
}
```

## Error Handling

```dart
try {
  final connection = await DatabaseFactory.createConnection(config);

  try {
    final results = await connection.query('SELECT * FROM users');
    // Process results
  } finally {
    await connection.close();
  }
} catch (e) {
  if (e is UnimplementedError) {
    print('Database not configured: $e');
  } else {
    print('Database error: $e');
  }
}
```

## Best Practices

1. **Always close connections:**

   ```dart
   final connection = await DatabaseFactory.createConnection(config);
   try {
     // Use connection
   } finally {
     await connection.close();
   }
   ```

2. **Use connection pooling for multiple operations:**

   ```dart
   final pool = await DatabaseFactory.createPool(config);
   // Reuse pool for multiple requests
   ```

3. **Use transactions for multiple related operations:**

   ```dart
   final transaction = await connection.beginTransaction();
   try {
     // Multiple operations
     await transaction.commit();
   } catch (e) {
     await transaction.rollback();
   }
   ```

4. **Use named parameters to prevent SQL injection:**

   ```dart
   // Good
   await connection.query(
     'SELECT * FROM users WHERE email = @email',
     parameters: {'email': userInput},
   );

   // Bad - vulnerable to SQL injection
   await connection.query('SELECT * FROM users WHERE email = "$userInput"');
   ```

## Examples

See the `/examples` folder for complete working examples:

- `db_postgres_dorm_example/` - Full ORM usage with PostgreSQL
- `example/database_connections_example.dart` - All database connection types

---

## Using with @Db Annotation

When using the `@Db` annotation, you can configure the connection directly:

```dart
@Db(
  entities: [UserEntity, PostEntity],
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
  DatabaseConnection? _connection;
  DatabaseConnection? get connection => _connection;
}
```

Then use the generated `setup()` or `init()` methods:

```dart
final db = Database();

// Option 1: Full setup with migrations
await db.setup(
  migrations: [Migration001()],
  validateSchema: true,
);

// Option 2: Just initialize connection
await db.init();

// Option 3: Override config at runtime
await db.init(DatabaseConfig.postgresql(
  host: 'production-host',
  port: 5432,
  database: 'prod_db',
  username: 'prod_user',
  password: 'prod_password',
));
```

---

## Troubleshooting

### PostgreSQL Connection Issues

- Verify PostgreSQL is running: `pg_isready`
- Check credentials and database name
- Ensure port 5432 is accessible
- Check SSL settings if using SSL

### SQLite3 Issues

- Verify file path is writable
- Check file permissions
- Use `:memory:` for testing

### MySQL Issues (When Enabled)

- Verify MySQL is running: `mysql -u root -p`
- Check credentials and database name
- Ensure port 3306 is accessible
- Uncomment all implementation code in `mysql_connection.dart`

---

## API Reference

### DatabaseConnection Methods

| Method                        | Return Type                          | Description                    |
| ----------------------------- | ------------------------------------ | ------------------------------ |
| `query(sql, {parameters})`    | `Future<List<Map<String, dynamic>>>` | Execute SELECT query           |
| `execute(sql, {parameters})`  | `Future<int>`                        | Execute INSERT/UPDATE/DELETE   |
| `rawQuery(sql, {parameters})` | `Future<List<List<dynamic>>>`        | Execute query with raw results |
| `beginTransaction()`          | `Future<DatabaseTransaction>`        | Start a transaction            |
| `close()`                     | `Future<void>`                       | Close the connection           |
| `isOpen`                      | `bool`                               | Check if connection is open    |
| `databaseType`                | `DatabaseType`                       | Get the database type          |

### DatabaseTransaction Methods

| Method                       | Return Type                          | Description                      |
| ---------------------------- | ------------------------------------ | -------------------------------- |
| `query(sql, {parameters})`   | `Future<List<Map<String, dynamic>>>` | Execute query in transaction     |
| `execute(sql, {parameters})` | `Future<int>`                        | Execute statement in transaction |
| `commit()`                   | `Future<void>`                       | Commit the transaction           |
| `rollback()`                 | `Future<void>`                       | Rollback the transaction         |
