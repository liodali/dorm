# Code Generation Output Configuration

## Overview

DORM uses `build_runner` to generate code from your annotated classes. This document explains where generated files are placed and how to configure the generation.

## Generated File Types

| Annotation                       | Generated File | Description                           |
| -------------------------------- | -------------- | ------------------------------------- |
| `@Entity`                        | `.orm.g.dart`  | Repository with CRUD, fromRow/toRow   |
| `@Db`                            | `.db.g.dart`   | Repository access, lifecycle, schemas |
| `@Db` (with `generateSql: true`) | `.sql`         | SQL CREATE TABLE statements           |

## Generated File Locations

### Entity Repositories (`.orm.g.dart`)

Generated **in the same directory** as the source entity file:

| Source File                       | Generated File                          |
| --------------------------------- | --------------------------------------- |
| `lib/src/models/user_entity.dart` | `lib/src/models/user_entity.orm.g.dart` |
| `lib/src/models/post_entity.dart` | `lib/src/models/post_entity.orm.g.dart` |
| `lib/entities/product.dart`       | `lib/entities/product.orm.g.dart`       |

### Database Extensions (`.db.g.dart`)

Generated **in the same directory** as the database class file:

| Source File                | Generated File                  |
| -------------------------- | ------------------------------- |
| `lib/src/db.dart`          | `lib/src/db.db.g.dart`          |
| `lib/database/app_db.dart` | `lib/database/app_db.db.g.dart` |

### SQL Files (`.sql`)

Generated in `.dart_tool/dorm/` when `generateSql: true`:

| Database Name  | Generated File                     |
| -------------- | ---------------------------------- |
| `mydb`         | `.dart_tool/dorm/mydb.sql`         |
| `app_database` | `.dart_tool/dorm/app_database.sql` |

---

## Directory Structure Example

```
your_project/
├── lib/
│   └── src/
│       ├── models/
│       │   ├── user_entity.dart
│       │   ├── user_entity.orm.g.dart    # Generated repository
│       │   ├── post_entity.dart
│       │   └── post_entity.orm.g.dart    # Generated repository
│       ├── db.dart
│       └── db.db.g.dart                  # Generated database extensions
├── .dart_tool/
│   └── dorm/
│       └── mydb.sql                      # Generated SQL (if enabled)
└── pubspec.yaml
```

---

## Using Generated Code

### Import Repositories

```dart
// Import from the same directory as the entity
import 'package:your_package/src/models/user_entity.dart';
import 'package:your_package/src/models/user_entity.orm.g.dart';

// Or import the database class which provides repository access
import 'package:your_package/src/db.dart';
```

### Access via Database Class

```dart
final db = Database();
await db.init();

// Access repositories via generated extension
final users = await db.userEntityRepository.getAll();
final posts = await db.postEntityRepository.query().toList();
```

---

## Build Configuration

### Default Configuration

The DORM package includes a `build.yaml` that handles most cases automatically.

### Custom Configuration

Create a `build.yaml` in your project root for custom settings:

```yaml
targets:
  $default:
    builders:
      dorm|entity:
        enabled: true
        generate_for:
          include:
            - lib/**/*.dart
      dorm|db:
        enabled: true
        generate_for:
          include:
            - lib/**/*.dart
      dorm|db_schema:
        enabled: true
        generate_for:
          include:
            - lib/**/*.dart
```

---

## Running Code Generation

### One-time Build

```bash
dart run build_runner build
```

### Watch Mode (Auto-rebuild on Changes)

```bash
dart run build_runner watch
```

### Clean Build (Delete Conflicting Files)

```bash
dart run build_runner build --delete-conflicting-outputs
```

---

## Version Control

### Recommended `.gitignore`

```gitignore
# Build artifacts
.dart_tool/
build/

# Generated files (optional - can commit or ignore)
# *.g.dart
```

### Should You Commit Generated Files?

**Option 1: Commit generated files** (Recommended for libraries)

- Faster CI/CD builds
- No build_runner dependency for consumers

**Option 2: Ignore generated files** (Recommended for apps)

- Smaller repository
- Always fresh generated code

---

## Troubleshooting

### Generated files not appearing

```bash
dart run build_runner build --delete-conflicting-outputs
```

### Import errors

Ensure you're importing from the correct location (same directory as source file).

### Part directive errors

Ensure your entity file has the correct `part` directive:

```dart
// user_entity.dart
import 'package:dorm/dorm.dart';

part 'user_entity.orm.g.dart';  // Must match generated filename

@Entity(tableName: 'users')
class UserEntity { ... }
```

### SQL file not generated

Ensure `generateSql: true` is set in your `@Db` annotation:

```dart
@Db(
  entities: [UserEntity],
  migrationVersion: 1,
  generateSql: true,  // Enable SQL generation
  name: 'mydb',
)
class Database { ... }
```
