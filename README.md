# DORM - Dart Object-Relational Mapping

A powerful ORM for Dart inspired by Hibernate (Java) and Entity Framework (C#) with LINQ-style query syntax.

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

- Repository pattern
- Unit of Work
- Transactions
- Connection pooling

🚀 **Advanced Features**

- Raw SQL queries
- Stored procedures
- Code generation
- Migration support

## Quick Start

```dart
import 'package:dorm/dorm.dart';

// Configure connection
final config = DatabaseConfig.postgresql(
  host: 'localhost',
  port: 5432,
  database: 'mydb',
  username: 'user',
  password: 'password',
);

// Create connection
final connection = await DatabaseFactory.createConnection(config);

// Use repository with LINQ-style queries
final users = await userRepo
    .query()
    .where('email LIKE @pattern', {'pattern': '%@example.com'})
    .orderByDescending('created_at')
    .take(10)
    .toList();
```

See `/example` folder for complete examples.

## Documentation

- **Connection Management**: Database abstraction layer supporting PostgreSQL, MySQL, SQLite
- **Repository Pattern**: Type-safe CRUD operations
- **Query Builder**: LINQ-style fluent API
- **Transactions**: Full transaction support
- **Connection Pooling**: Efficient connection management

## Database Support Status

| Database   | Status               | Package Required   | Notes                    |
| ---------- | -------------------- | ------------------ | ------------------------ |
| PostgreSQL | ✅ Fully Implemented | `postgres: ^2.6.0` | Production ready         |
| SQLite3    | ✅ Fully Implemented | `sqlite3: ^3.0.1`  | Production ready         |
| MySQL      | 🔧 Structure Ready   | `not defined`  | Uncomment code to enable |

### Enabling MySQL Support

1. Add to `pubspec.yaml`:

```yaml
dependencies:
  mysql1: ^0.20.0
```

2. Uncomment the implementation code in `lib/src/database/mysql_connection.dart`

3. Use like PostgreSQL:

```dart
final config = DatabaseConfig.mysql(
  host: 'localhost',
  port: 3306,
  database: 'mydb',
  username: 'root',
  password: 'password',
);
```
