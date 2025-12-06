# DormQL Analyzer Plugin

A Dart analyzer plugin that provides static analysis for DormQL annotations. It validates entity configurations, relationship mappings, and database schema definitions at development time.

## Features

### Entity Validation Rules

| Rule                 | Code                                   | Severity | Description                                                              |
| -------------------- | -------------------------------------- | -------- | ------------------------------------------------------------------------ |
| **Missing ID**       | `dormql_missing_id`                    | Error    | Ensures every `@Entity` class has a primary key (`@Id` or `@PrimaryKey`) |
| **Multiple IDs**     | `dormql_multiple_ids`                  | Warning  | Prevents multiple `@Id` annotations in a single entity                   |
| **ID Type Mismatch** | `dormql_uuid_requires_string`          | Error    | UUID strategy requires `String` type                                     |
| **ID Type Mismatch** | `dormql_autoincrement_requires_int`    | Error    | AutoIncrement/Serial requires `int` or `BigInt`                          |
| **ID Nullable**      | `dormql_id_nullable_not_allowed`       | Error    | ID field cannot be nullable when `autoIncrement: false`                  |
| **ID Conflict**      | `dormql_id_primarykey_conflict`        | Warning  | Prevents using both `@Id` and `@PrimaryKey` together                     |
| **Field Conflict**   | `dormql_id_column_primarykey_conflict` | Warning  | Prevents `@Id` + `@Column(primaryKey: true)` on same field               |
| **Column Type**      | `dormql_column_type_mismatch`          | Warning  | Validates `@Column` columnType matches Dart field type                   |

### @OneToOne Relationship Rules

| Rule                   | Code                                    | Severity | Description                                       |
| ---------------------- | --------------------------------------- | -------- | ------------------------------------------------- |
| **Missing Target**     | `dormql_onetoone_missing_target`        | Error    | `@OneToOne` must specify `targetEntity` parameter |
| **Invalid Target**     | `dormql_onetoone_invalid_target`        | Error    | `targetEntity` must be an `@Entity` class         |
| **MappedBy Not Found** | `dormql_onetoone_mappedby_not_found`    | Error    | `mappedBy` field must exist in target entity      |
| **MappedBy Invalid**   | `dormql_onetoone_mappedby_not_onetoone` | Error    | `mappedBy` field must have `@OneToOne` annotation |

### Other Relationship Validation (Planned)

- `@OneToMany`, `@ManyToOne`, `@ManyToMany` configuration checks
- Join table configuration validation

### Database Version Checking (Planned)

- Schema change detection
- Migration version bump warnings

## Getting Started

### Requirements

- Dart SDK `^3.10.1`
- `analyzer` `^9.0.0`

### Installation

Add the plugin to your project's `analysis_options.yaml`:

```yaml
analyzer:
  plugins:
    - dormql_analyzer_plugin
```

Add the dependency to your `pubspec.yaml`:

```yaml
dev_dependencies:
  dormql_analyzer_plugin: ^0.1.0
```

## Usage

Once configured, the plugin automatically analyzes your DormQL entities and reports issues in your IDE.

### Example: Valid Entity

```dart
@Entity(tableName: 'users')
class UserEntity {
  @Id()
  int id;

  String name;
  String email;
}
```

### Example: Invalid - Missing ID

```dart
@Entity(tableName: 'posts')
class PostEntity {  // Error: Entity must have a primary key
  String title;
  String content;
}
```

### Example: Invalid - UUID Type Mismatch

```dart
@Entity(tableName: 'documents')
class DocumentEntity {
  @Id.uuid()
  int id;  // Error: UUID strategy requires String type

  String content;
}
```

### Example: Invalid - Multiple IDs

```dart
@Entity(tableName: 'items')
class ItemEntity {
  @Id()
  int id;

  @Id()  // Error: Multiple @Id annotations
  String uuid;
}
```

### Example: Invalid - Nullable ID with UUID

```dart
@Entity(tableName: 'documents')
class DocumentEntity {
  @Id.uuid()
  String? id;  // Error: ID cannot be nullable when autoIncrement is false

  String content;
}
```

## Quick Fixes

The plugin provides quick fixes for common issues:

| Diagnostic                       | Fix                         | Description                             |
| -------------------------------- | --------------------------- | --------------------------------------- |
| `dormql_missing_id`              | Add `@Id() int id;`         | Adds an auto-increment integer ID field |
| `dormql_missing_id`              | Add `@Id.uuid() String id;` | Adds a UUID string ID field             |
| `dormql_id_nullable_not_allowed` | Remove `?` from type        | Removes nullable marker from ID field   |

## Diagnostics

Diagnostics are registered with appropriate severity levels:

- **Error**: Critical issues that must be fixed (e.g., missing ID, nullable ID with autoIncrement=false)
- **Warning**: Best practice violations that should be addressed

## Architecture

```
lib/src/
├── dormql_analyzer_plugin.dart     # Main plugin entry
├── utils/
│   └── annotation_checker.dart     # AST annotation utilities
├── visitor/
│   └── entity_visitor.dart         # Entity AST visitor
├── rules/
│   └── entity/
│       ├── missing_id_rule.dart
│       ├── multiple_ids_rule.dart
│       ├── id_type_mismatch_rule.dart
│       ├── id_nullable_rule.dart
│       └── id_primarykey_conflict_rule.dart
└── fixes/
    ├── add_id_fix.dart             # Quick fix for missing ID
    └── remove_nullable_fix.dart    # Quick fix for nullable ID
```

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## License

See the LICENSE file for details.
