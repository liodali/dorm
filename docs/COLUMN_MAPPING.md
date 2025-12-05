# Column Name Mapping Guide

## Overview

DORM automatically generates `fromRow()` and `toRow()` methods that map between Dart field names and database column names. This document explains the mapping rules and available annotations.

## Mapping Rules

### Priority Order

1. **`@Column(name: 'custom_name')`** - Explicit custom name takes highest priority
2. **camelCase → snake_case** - Automatic conversion for camelCase fields
3. **snake_case unchanged** - Fields already in snake_case remain as-is

### 1. Custom Column Names

Use `@Column(name: 'custom_name')` to specify exact column name:

```dart
@Column(name: 'user_email')
final String email;
```

**Result:** Field `email` maps to column `user_email`

### 2. Automatic camelCase → snake_case Conversion

Field names in camelCase are automatically converted to snake_case:

```dart
final String firstName;      // → first_name
final DateTime? createdAt;   // → created_at
final String productCode;    // → product_code
final int userId;            // → user_id
final bool isActive;         // → is_active
```

### 3. snake_case Fields Unchanged

Fields already in snake_case remain as-is:

```dart
final String? phone_number;  // → phone_number (unchanged)
```

### 4. Fields Without @Column Annotation

**All fields are automatically included** unless marked with `@Ignore` or relationship annotations. You don't need to add `@Column` to every field.

## Conversion Examples

| Dart Field Name | Database Column Name |
| --------------- | -------------------- |
| `id`            | `id`                 |
| `name`          | `name`               |
| `firstName`     | `first_name`         |
| `lastName`      | `last_name`          |
| `email`         | `email`              |
| `phoneNumber`   | `phone_number`       |
| `dateOfBirth`   | `date_of_birth`      |
| `createdAt`     | `created_at`         |
| `updatedAt`     | `updated_at`         |
| `isActive`      | `is_active`          |
| `hasAccess`     | `has_access`         |
| `productCode`   | `product_code`       |
| `orderTotal`    | `order_total`        |
| `userId`        | `user_id`            |
| `blogId`        | `blog_id`            |

## Complete Example

### Entity Definition

```dart
@Entity(tableName: 'users')
class User {
  @Id(autoIncrement: true)
  final int? id;

  // Auto-converted: firstName → first_name
  @Column(nullable: false)
  final String firstName;

  // Auto-converted: lastName → last_name
  @Column(nullable: false)
  final String lastName;

  // Custom name: email → user_email
  @Column(name: 'user_email', nullable: false, unique: true)
  final String email;

  // Auto-converted: phoneNumber → phone_number
  @Column(nullable: true)
  final String? phoneNumber;

  // Auto-converted: dateOfBirth → date_of_birth
  @Column(nullable: true)
  final DateTime? dateOfBirth;

  // Auto-converted: createdAt → created_at
  @Column(nullable: true)
  final DateTime? createdAt;

  // Ignored - not in database
  @Ignore()
  final String? tempData;

  const User({
    this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.phoneNumber,
    this.dateOfBirth,
    this.createdAt,
    this.tempData,
  });
}
```

### Generated Repository

```dart
class UserRepository extends Repository<User> {
  UserRepository() : super('users');

  @override
  User fromRow(Map<String, dynamic> row) {
    return User(
      id: row['id'] as int?,
      firstName: row['first_name'] as String,        // Mapped
      lastName: row['last_name'] as String,          // Mapped
      email: row['user_email'] as String,            // Custom
      phoneNumber: row['phone_number'] as String?,   // Mapped
      dateOfBirth: row['date_of_birth'] != null
          ? DateTime.parse(row['date_of_birth'] as String)
          : null,                                     // Mapped
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : null,                                     // Mapped
    );
  }

  @override
  Map<String, dynamic> toRow(User entity) {
    return {
      'id': entity.id,
      'first_name': entity.firstName,                // Mapped
      'last_name': entity.lastName,                  // Mapped
      'user_email': entity.email,                    // Custom
      'phone_number': entity.phoneNumber,            // Mapped
      'date_of_birth': entity.dateOfBirth?.toIso8601String(),  // Mapped
      'created_at': entity.createdAt?.toIso8601String(),       // Mapped
    };
  }
}
```

### Generated SQL Schema

```sql
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  first_name VARCHAR(255) NOT NULL,
  last_name VARCHAR(255) NOT NULL,
  user_email VARCHAR(255) NOT NULL UNIQUE,
  phone_number VARCHAR(255),
  date_of_birth TIMESTAMP,
  created_at TIMESTAMP
);
```

## Type Conversions

The generator also handles type conversions automatically:

### DateTime Fields

```dart
// Dart
final DateTime? createdAt;

// fromRow
createdAt: row['created_at'] != null
    ? DateTime.parse(row['created_at'] as String)
    : null

// toRow
'created_at': entity.createdAt?.toIso8601String()
```

### Numeric Fields

```dart
// Dart
final int age;
final double price;

// fromRow
age: row['age'] as int
price: (row['price'] as num).toDouble()

// toRow
'age': entity.age
'price': entity.price
```

### Boolean Fields

```dart
// Dart
final bool isActive;

// fromRow
isActive: row['is_active'] as bool

// toRow
'is_active': entity.isActive
```

### String Fields

```dart
// Dart
final String name;
final String? description;

// fromRow
name: row['name'] as String
description: row['description'] as String?

// toRow
'name': entity.name
'description': entity.description
```

## Foreign Keys

Foreign key fields follow the same naming rules:

```dart
@Entity(tableName: 'posts')
class Post {
  @Id(autoIncrement: true)
  final int? id;

  @Column(nullable: false)
  final String title;

  // Auto-converted: blogId → blog_id
  @Column(nullable: false)
  final int blogId;

  // Relationship field (not a column)
  @ManyToOne(targetEntity: Blog)
  final Blog? blog;
}
```

**Generated SQL:**

```sql
CREATE TABLE posts (
  id SERIAL PRIMARY KEY,
  title VARCHAR(255) NOT NULL,
  blog_id INTEGER NOT NULL,
  FOREIGN KEY (blog_id) REFERENCES blogs(id)
);
```

## Best Practices

### ✅ Recommended

```dart
// Use camelCase in Dart
final String firstName;
final DateTime createdAt;
final int userId;

// Use custom names for clarity when needed
@Column(name: 'user_email')
final String email;

@Column(name: 'account_status')
final String status;
```

### ❌ Avoid

```dart
// Don't mix naming conventions
final String first_name;  // Use firstName instead
final String FirstName;   // Use firstName instead

// Don't use unclear abbreviations
final String fn;          // Use firstName instead
final String dob;         // Use dateOfBirth instead
```

## Summary

| Feature           | Behavior                                |
| ----------------- | --------------------------------------- |
| **Custom Names**  | `@Column(name: 'custom')` → exact match |
| **camelCase**     | Converted to `snake_case`               |
| **snake_case**    | Unchanged                               |
| **PascalCase**    | Converted to `snake_case`               |
| **@Ignore**       | Skipped entirely                        |
| **Relationships** | Not mapped (not columns)                |

The generator ensures consistent, predictable mapping between your Dart code and database schema!

---

## @Column Annotation Reference

```dart
class Column {
  /// Custom column name (overrides automatic conversion)
  final String? name;

  /// Whether this is a primary key
  final bool primaryKey;

  /// Whether the column allows NULL values
  final bool nullable;

  /// Whether the column has a UNIQUE constraint
  final bool unique;

  /// Default value (SQL expression as string)
  final String? defaultValue;

  /// Column length (for VARCHAR, etc.)
  final int? length;

  /// Column type hint
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
```

### ColumnType Enum

```dart
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
```

---

## @Id Annotation Reference

```dart
class Id {
  /// Whether the ID auto-increments
  final bool autoIncrement;

  /// ID generation strategy (SERIAL, UUID, IDENTITY, etc.)
  final String? strategy;

  // Factory constructors for different databases
  const Id.postgres({autoIncrement = true, strategy = 'SERIAL'});
  const Id.mysql({autoIncrement = true, strategy = 'AUTO_INCREMENT'});
  const Id.sqlite({autoIncrement = true, strategy = 'AUTOINCREMENT'});
  const Id({autoIncrement = true, strategy = 'AUTOINCREMENT'});
}
```

---

## @Ignore Annotation

Use `@Ignore()` to exclude fields from database mapping:

```dart
@Entity(tableName: 'users')
class UserEntity {
  @Id()
  int? id;

  String name;
  String email;

  @Ignore()
  String? temporaryData;  // Not persisted to database

  @Ignore()
  bool isSelected = false;  // UI state, not persisted
}
```

---

## Complete Annotation Example

```dart
@Entity(tableName: 'products', dbType: DatabaseType.postgresql)
@Index(columns: ['sku'], unique: true, name: 'idx_products_sku')
class ProductEntity {
  @Id()
  int? id;

  @Column(nullable: false, unique: true)
  String sku;

  @Column(name: 'product_name', nullable: false)
  String name;

  @Column(columnType: ColumnType.decimal, nullable: false)
  double price;

  @Column(nullable: true, length: 1000)
  String? description;

  @Column(nullable: false, defaultValue: 'true')
  bool isActive;

  DateTime? createdAt;  // Auto-mapped to created_at
  DateTime? updatedAt;  // Auto-mapped to updated_at

  @Ignore()
  double? discountedPrice;  // Computed, not stored

  ProductEntity({
    this.id,
    required this.sku,
    required this.name,
    required this.price,
    this.description,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });
}
```
