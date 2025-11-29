# DORM Code Generation System

## Overview

DORM provides a comprehensive code generation system using `build_runner` that automatically generates:

1. **Entity Repositories** (`.orm.g.dart`) - CRUD operations, `fromRow()`, `toRow()` methods
2. **Database Class Extensions** (`.db.g.dart`) - Repository access, lifecycle methods, schema definitions
3. **SQL Schema Files** (`.sql`) - CREATE TABLE statements for all entities
4. **Relationship Loading** - `include()` functionality for eager loading

## Architecture

```
Source Files                    Generated Files
─────────────────────────────────────────────────────────────────
@Entity class
  user_entity.dart      →       user_entity.orm.g.dart (Repository)

@Db class
  db.dart               →       db.db.g.dart (Extensions + Schemas)
                        →       .dart_tool/dorm/<name>.sql (SQL file)
```

## Generators

| Generator             | Input             | Output        | Description                           |
| --------------------- | ----------------- | ------------- | ------------------------------------- |
| `entity_generator`    | `@Entity` classes | `.orm.g.dart` | Repository with CRUD, fromRow/toRow   |
| `db_generator`        | `@Db` classes     | `.db.g.dart`  | Repository access, lifecycle, schemas |
| `db_schema_generator` | `@Db` classes     | `.sql` files  | SQL CREATE TABLE statements           |

## 1. Entity Generation

### Column Name Mapping

The generator automatically maps Dart field names to database column names:

**Rules:**

1. If `@Column(name: 'custom_name')` is specified, use that name
2. Otherwise, convert `camelCase` to `snake_case`
3. Field names already in `snake_case` remain unchanged

**Examples:**

```dart
firstName       → first_name
lastName        → last_name
dateOfBirth     → date_of_birth
createdAt       → created_at
phone_number    → phone_number (unchanged)

@Column(name: 'user_email')
email           → user_email (custom)
```

### Input: Annotated Entity Class

```dart
@Entity(tableName: 'blogs', dbType: DatabaseType.postgresql)
class Blog {
  @Id(autoIncrement: true)
  final int? id;

  // Auto-converted to 'title' (already lowercase)
  @Column(nullable: false)
  final String title;

  // Auto-converted to 'created_at'
  @Column(nullable: true)
  final DateTime? createdAt;

  // Custom column name
  @Column(name: 'blog_description', nullable: true)
  final String? description;

  @OneToMany(targetEntity: Post, mappedBy: 'blogId')
  final List<Post>? posts;

  const Blog({
    this.id,
    required this.title,
    this.createdAt,
    this.description,
    this.posts
  });
}
```

### Output: Generated Repository

```dart
// Generated code for Blog
part of 'blog.dart';

class BlogRepository extends Repository<Blog> {
  BlogRepository() : super('blogs');

  @override
  Blog fromRow(Map<String, dynamic> row) {
    return Blog(
      id: row['id'] as int?,
      title: row['title'] as String,
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : null,
      description: row['blog_description'] as String?,  // Custom name
    );
  }

  @override
  Map<String, dynamic> toRow(Blog entity) {
    return {
      'id': entity.id,
      'title': entity.title,
      'created_at': entity.createdAt?.toIso8601String(),
      'blog_description': entity.description,  // Custom name
    };
  }

  @override
  Future<void> loadRelationships(Blog entity, List<String> includes) async {
    for (final include in includes) {
      switch (include) {
        case 'posts':
          // Load OneToMany relationship for posts
          final postRepo = PostRepository();
          postRepo.setConnection(connection);
          final postsData = await postRepo.query()
            .where('blog_id = @id', {'id': entity.id})
            .toList();
          // Note: Requires mutable entity or copyWith pattern
          break;
        default:
          throw Exception('Unknown relationship: $include');
      }
    }
  }
}
```

## 2. Relationship Types & Code Generation

### OneToMany

**Annotation:**

```dart
@OneToMany(targetEntity: Post, mappedBy: 'blogId')
final List<Post>? posts;
```

**Generated Code:**

```dart
case 'posts':
  final postRepo = PostRepository();
  postRepo.setConnection(connection);
  final postsData = await postRepo.query()
    .where('blog_id = @id', {'id': entity.id})
    .toList();
  break;
```

### ManyToOne

**Annotation:**

```dart
@ManyToOne(targetEntity: Blog, eagerLoad: false)
final Blog? blog;
```

**Generated Code:**

```dart
case 'blog':
  final blogRepo = BlogRepository();
  blogRepo.setConnection(connection);
  final blogData = await blogRepo.findById(entity.blogId);
  break;
```

### ManyToMany

**Annotation:**

```dart
@ManyToMany(
  targetEntity: Course,
  joinTableName: 'student_courses',
  inverseFieldName: 'students',
)
final List<Course>? courses;
```

**Generated Code:**

```dart
case 'courses':
  final sql = 'SELECT t.* FROM courses t INNER JOIN student_courses jt ON t.id = jt.course_id WHERE jt.students_id = @id';
  final results = await connection.query(sql, parameters: {'id': entity.id});
  final courseRepo = CourseRepository();
  courseRepo.setConnection(connection);
  final coursesData = results.map((r) => courseRepo.fromRow(r)).toList();
  break;
```

## 3. Schema Generation

### Generated Schema Structure

```json
{
  "tableName": "posts",
  "columns": [
    {
      "name": "id",
      "type": "INTEGER",
      "nullable": false,
      "primaryKey": true,
      "unique": false,
      "defaultValue": null
    },
    {
      "name": "title",
      "type": "VARCHAR(255)",
      "nullable": false,
      "primaryKey": false,
      "unique": false,
      "defaultValue": null
    },
    {
      "name": "blog_id",
      "type": "INTEGER",
      "nullable": false,
      "primaryKey": false,
      "unique": false,
      "defaultValue": null
    }
  ],
  "foreignKeys": [
    {
      "column": "blog_id",
      "referencedTable": "blogs",
      "referencedColumn": "id"
    }
  ],
  "indexes": []
}
```

### Foreign Key Detection

The system automatically detects foreign keys based on naming conventions:

- Fields ending with `Id` (e.g., `blogId`)
- Fields ending with `_id` (e.g., `blog_id`)

The referenced table is inferred by:

1. Removing the `Id` or `_id` suffix
2. Converting to snake_case
3. Pluralizing (adding 's')

Example: `blogId` → `blogs`

## 4. Migration Generation

### Initial Migration (First Time)

When no previous schema exists, an initial CREATE TABLE migration is generated:

```dart
class Migration1700000000_CreateBlogs extends DatabaseMigration {
  @override
  int get version => 1700000000;

  @override
  String get description => 'Create blogs table';

  @override
  DatabaseType get dbType => DatabaseType.postgresql;

  @override
  Future<void> Up() async {
    const sql = '''
      CREATE TABLE IF NOT EXISTS blogs (
        id SERIAL PRIMARY KEY,
        title VARCHAR(255) NOT NULL,
        description TEXT,
        created_at TIMESTAMP
      );
    ''';

    await connection.execute(sql);
  }

  @override
  Future<void> Down() async {
    const sql = 'DROP TABLE IF EXISTS blogs CASCADE;';
    await connection.execute(sql);
  }
}
```

### Diff Migration (Schema Changes)

When the schema changes, a diff migration is generated:

```dart
class Migration1700000100_UpdateBlogs extends DatabaseMigration {
  @override
  int get version => 1700000100;

  @override
  String get description => 'Update blogs table schema';

  @override
  DatabaseType get dbType => DatabaseType.postgresql;

  @override
  Future<void> Up() async {
    await connection.execute('''
      ALTER TABLE blogs ADD COLUMN author_id INTEGER;
      ALTER TABLE blogs ADD COLUMN status VARCHAR(50) NOT NULL DEFAULT 'draft';
    ''');
  }

  @override
  Future<void> Down() async {
    await connection.execute('''
      ALTER TABLE blogs DROP COLUMN status;
      ALTER TABLE blogs DROP COLUMN author_id;
    ''');
  }
}
```

### Schema Change Detection

The system detects:

- **Added Columns**: New fields in entity
- **Removed Columns**: Deleted fields from entity
- **Modified Columns**: Type, nullability, or constraint changes

## 5. Build Configuration

### pubspec.yaml

```yaml
dependencies:
  dorm:
    git:
      url: https://github.com/liodali/dorm.git
  postgres: ^3.1.0 # For PostgreSQL
  sqlite3: ^3.0.1 # For SQLite

dev_dependencies:
  build_runner: ^2.4.0
```

### build.yaml

The default `build.yaml` in the DORM package handles most cases. For custom configurations:

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

## 6. Usage Workflow

### Step 1: Define Entity

```dart
// lib/models/blog.dart
import 'package:dorm/dorm.dart';

part 'blog.g.dart';

@Entity(tableName: 'blogs')
class Blog {
  @Id(autoIncrement: true)
  final int? id;

  @Column(nullable: false)
  final String title;

  @OneToMany(targetEntity: Post, mappedBy: 'blogId')
  final List<Post>? posts;

  const Blog({this.id, required this.title, this.posts});
}
```

### Step 2: Run Code Generation

```bash
# Generate repository code
dart run build_runner build

# Or watch for changes
dart run build_runner watch
```

### Step 3: Generated Files

```
lib/models/
  ├── blog.dart
  ├── blog.g.dart          # Generated repository
  └── blog.schema.json     # Generated schema

lib/migrations/
  └── migration_1700000000_create_blogs.dart
```

### Step 4: Use Generated Code

```dart
void main() async {
  final connection = await DatabaseFactory.createConnection(config);

  final blogRepo = BlogRepository();
  blogRepo.setConnection(connection);

  // Use include for eager loading
  final blogs = await blogRepo
      .query()
      .include('posts')  // Load related posts
      .toList();

  // Run migrations
  final migrations = [Migration1700000000_CreateBlogs()];
  final runner = MigrationRunner(connection, migrations);
  await runner.runMigrations();
}
```

## 7. Advanced Features

### @Ignore Annotation

Skip fields during code generation:

```dart
@Entity(tableName: 'users')
class User {
  @Column(nullable: false)
  final String name;

  @Ignore()
  final String? cachedData;  // Not persisted
}
```

### Custom Column Names

```dart
@Column(name: 'user_email', nullable: false, unique: true)
final String email;
```

### Indexes

```dart
@Index(columns: ['email', 'status'], unique: true)
@Entity(tableName: 'users')
class User {
  // ...
}
```

### Cascade Delete

```dart
@OneToMany(
  targetEntity: Post,
  mappedBy: 'blogId',
  cascadeDelete: true,  // Delete posts when blog is deleted
)
final List<Post>? posts;
```

## 8. Migration Strategy

### Development

During development, you can:

1. Modify entities freely
2. Delete old migrations
3. Regenerate fresh migrations
4. Reset database

### Production

In production:

1. Never delete applied migrations
2. Always generate new migrations for changes
3. Test migrations on staging first
4. Keep rollback (Down) methods functional

### Migration Versioning

Migrations use timestamp-based versioning:

- Format: `UNIX_TIMESTAMP`
- Example: `1700000000`
- Ensures chronological order
- Prevents conflicts in team environments

## 9. Best Practices

### 1. Entity Design

```dart
// ✅ Good: Immutable entity with relationships
@Entity(tableName: 'blogs')
class Blog {
  final int? id;
  final String title;
  final List<Post>? posts;

  const Blog({this.id, required this.title, this.posts});

  Blog copyWith({List<Post>? posts}) {
    return Blog(id: id, title: title, posts: posts ?? this.posts);
  }
}
```

### 2. Foreign Key Naming

```dart
// ✅ Good: Clear foreign key naming
final int blogId;  // References blogs table
final int authorId;  // References authors table

// ❌ Avoid: Ambiguous naming
final int blog;
final int author;
```

### 3. Relationship Mapping

```dart
// ✅ Good: Explicit mappedBy
@OneToMany(targetEntity: Post, mappedBy: 'blogId')
final List<Post>? posts;

// ❌ Avoid: Missing mappedBy
@OneToMany(targetEntity: Post)
final List<Post>? posts;
```

### 4. Include Usage

```dart
// ✅ Good: Load only what you need
final blogs = await blogRepo.query().include('posts').toList();

// ❌ Avoid: Over-fetching
final blogs = await blogRepo.query()
    .include('posts')
    .include('author')
    .include('comments')
    .include('tags')
    .toList();
```

## 10. Troubleshooting

### Issue: Generated code not found

**Solution:** Run `dart run build_runner build`

### Issue: Foreign key not detected

**Solution:** Ensure field name ends with `Id` or `_id`

### Issue: Relationship not loading

**Solution:** Check `mappedBy` parameter matches foreign key field name

### Issue: Migration conflicts

**Solution:** Use timestamp-based versions, coordinate with team

## Summary

The DORM code generation system provides:

- ✅ Automatic repository generation with CRUD operations
- ✅ Relationship loading with `include()` for eager loading
- ✅ Schema management with foreign keys, indexes, and constraints
- ✅ SQL file generation for database setup
- ✅ Type-safe, compile-time code generation
- ✅ Automatic camelCase to snake_case column mapping
- ✅ Support for PostgreSQL and SQLite (MySQL coming soon)

This enables rapid development while maintaining type safety and database consistency.

## Generated Code Reference

### Entity Repository (`.orm.g.dart`)

```dart
class UserEntityRepository extends Repository<UserEntity> {
  UserEntityRepository() : super('users');

  @override
  UserEntity fromRow(Map<String, dynamic> row) {
    return UserEntity(
      id: row['id'] as int?,
      name: row['name'] as String,
      email: row['email'] as String,
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'].toString())
          : null,
    );
  }

  @override
  Map<String, dynamic> toRow(UserEntity entity) {
    return {
      'id': entity.id,
      'name': entity.name,
      'email': entity.email,
      'created_at': entity.createdAt?.toIso8601String(),
    };
  }

  @override
  Future<void> loadRelationships(UserEntity entity, List<String> includes) async {
    // Generated relationship loading code
  }
}
```

### Database Extensions (`.db.g.dart`)

```dart
// Repository access
extension DatabaseRepositories on Database {
  UserEntityRepository get userEntityRepository => ...;
  PostEntityRepository get postEntityRepository => ...;
}

// Lifecycle methods
extension DatabaseLifecycle on Database {
  static const int currentMigrationVersion = 1;

  Future<void> setup({...}) async { ... }
  Future<void> init([DatabaseConfig? config]) async { ... }
  Future<void> initializeDatabase({...}) async { ... }
  Future<void> close() async { ... }
}

// Schema definitions
const userEntitySchema = DatabaseSchema(
  tableName: 'users',
  columns: [...],
  foreignKeys: [...],
  indexes: [...],
);
```

### SQL File (`.dart_tool/dorm/<name>.sql`)

```sql
-- Database: mydb
-- Generated: 2024-01-15T10:30:00.000Z
-- Migration Version: 1

CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users (email);
```
