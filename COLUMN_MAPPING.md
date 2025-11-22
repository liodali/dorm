# Column Name Mapping Guide

## Overview

DORM automatically generates `fromRow()` and `toRow()` methods that map between Dart field names and database column names.

## Mapping Rules

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
@Column(nullable: false)
final String firstName;  // → first_name

@Column(nullable: true)
final DateTime? createdAt;  // → created_at

@Column(nullable: false)
final String productCode;  // → product_code
```

### 3. snake_case Fields Unchanged

Fields already in snake_case remain as-is:

```dart
@Column(nullable: true)
final String? phone_number;  // → phone_number (unchanged)
```

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
