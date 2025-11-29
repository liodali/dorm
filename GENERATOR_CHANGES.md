# Entity Generator Changes Summary

This document tracks changes to the DORM code generation system.

## Current Generator Behavior

### Output Location

Generated files are placed **in the same directory** as the source entity files (standard `build_runner` behavior):

| Source File                       | Generated File                          |
| --------------------------------- | --------------------------------------- |
| `lib/src/models/user_entity.dart` | `lib/src/models/user_entity.orm.g.dart` |
| `lib/src/db.dart`                 | `lib/src/db.db.g.dart`                  |

### File Processing

- **Entity files**: Any file with `@Entity` annotation (no filename requirements)
- **Database files**: Any file with `@Db` annotation
- **All fields included**: Fields are automatically included unless marked with `@Ignore`

### Column Name Mapping

- **camelCase → snake_case**: Automatic conversion
- **Custom names**: Use `@Column(name: 'custom_name')`
- **snake_case unchanged**: Fields already in snake_case remain as-is

---

## Version History

### v1.0.0 - Current

#### Features

1. **Flexible File Naming** ✅

   - Processes ANY file with `@Entity` annotation
   - No filename requirements (e.g., `_entity.dart` suffix not required)

2. **Automatic Field Processing** ✅

   - All fields included by default
   - No need to annotate every field with `@Column`
   - Use `@Ignore` to exclude fields

3. **Constructor Parameter Detection** ✅

   - Detects required vs optional fields from constructor
   - Generates correct `fromRow()` constructor calls

4. **Automatic Column Mapping** ✅

   - camelCase to snake_case conversion
   - Custom names via `@Column(name: 'custom')`

5. **Relationship Support** ✅

   - `@OneToOne`, `@OneToMany`, `@ManyToMany`
   - Generated repository methods for ManyToMany
   - Junction table generation

6. **SQL File Generation** ✅
   - `generateSql: true` in `@Db` annotation
   - Output to `.dart_tool/dorm/<name>.sql`

---

## File Structure

```
your_project/
├── lib/
│   └── src/
│       ├── models/
│       │   ├── user_entity.dart
│       │   ├── user_entity.orm.g.dart    # Generated
│       │   ├── post_entity.dart
│       │   └── post_entity.orm.g.dart    # Generated
│       ├── db.dart
│       └── db.db.g.dart                  # Generated
└── .dart_tool/
    └── dorm/
        └── mydb.sql                      # Generated SQL (if enabled)
```

## Usage

### Entity Definition (No changes needed)

```dart
@Entity(tableName: 'users', dbType: DatabaseType.postgresql)
class UserEntity {
  @Id()
  int? id;

  String name;        // ✅ Automatically included (no @Column needed)
  String email;       // ✅ Automatically included

  @Ignore()
  String? tempField;  // ❌ Excluded from generation

  UserEntity({
    this.id,
    required this.name,
    required this.email,
  });
}
```

### Import Generated Repository

```dart
// ✅ Clean import path
import 'package:your_package/db_gen/entities/user_entity.orm.g.dart';

final userRepo = UserEntityRepository();
```

## Next Steps

### To Complete Constructor Detection:

The `constructorParams` map is now being passed to `_generateRepositoryCode()` but not yet used. You need to update the `fromRow` generation to use it:

```dart
// Current (incorrect):
UserEntity fromRow(Map<String, dynamic> row) {
  return UserEntity(
    id: row['id'] as int?
  );
}

// Should be (using constructorParams):
UserEntity fromRow(Map<String, dynamic> row) {
  return UserEntity(
    id: row['id'] != null ? row['id'] as int : null,
    name: row['name'] as String,        // ✅ Required field
    email: row['email'] as String,      // ✅ Required field
  );
}
```

### Implementation Needed:

Update the `fromRowMappings` generation in `_generateRepositoryCode()` to:

1. Only include fields that are constructor parameters
2. Respect the required/optional status from `constructorParams`

## Build Command

```bash
# Clean build
dart run build_runner build --delete-conflicting-outputs

# Watch mode
dart run build_runner watch --delete-conflicting-outputs
```

## Migration Guide

### From Earlier Versions

If upgrading from an earlier version of DORM:

1. **Delete old generated files**: Remove any `.g.dart` files in `lib/db_gen/`
2. **Run build_runner**: `dart run build_runner build --delete-conflicting-outputs`
3. **Update imports**: Generated files are now in the same directory as source files

### Import Changes

```dart
// Old (if using db_gen folder)
import 'package:your_package/db_gen/entities/user_entity.orm.g.dart';

// New (same directory as source)
import 'package:your_package/src/models/user_entity.orm.g.dart';
```

---

## Troubleshooting

### Generated code not found

```bash
dart run build_runner build --delete-conflicting-outputs
```

### Import errors after regeneration

Check that imports point to the correct location (same directory as source file).

### Fields not being mapped

- Ensure field is not marked with `@Ignore`
- Ensure field is not a relationship annotation (`@OneToOne`, etc.)
- Check that field is in the constructor

### Column name incorrect

Use `@Column(name: 'exact_column_name')` to override automatic mapping.
