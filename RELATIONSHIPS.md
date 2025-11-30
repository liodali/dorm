# DORM Relationships & Include Syntax

## Overview

DORM supports Entity Framework-style relationship loading with the `include()` method, allowing you to eager load related entities in LINQ-style queries.

## Relationship Types Summary

| Annotation    | Description                             | FK Location    | Example        |
| ------------- | --------------------------------------- | -------------- | -------------- |
| `@OneToOne`   | One entity relates to exactly one other | Owning side    | User ↔ Profile |
| `@OneToMany`  | One entity relates to many others       | Target entity  | User → Posts   |
| `@ManyToOne`  | Many entities relate to one other       | This entity    | Post → User    |
| `@ManyToMany` | Many entities relate to many others     | Junction table | Users ↔ Roles  |

## Key Concepts

### Owning vs Inverse Side

- **Owning side** - Has the foreign key column (use `@ManyToOne` with `foreignKey`)
- **Inverse side** - References the owning side (use `@OneToMany` with `mappedBy`)

### RelationAction Enum

```dart
enum RelationAction {
  noAction,   // No action on delete/update
  restrict,   // Restrict delete/update if referenced
  cascade,    // Cascade delete/update to referencing rows
  setNull,    // Set to NULL on delete/update
  setDefault, // Set to default value on delete/update
}
```

---

## @OneToOne

Defines a one-to-one relationship between entities. One side owns the FK column.

### Annotation Reference

```dart
class OneToOne {
  final Type targetEntity;           // Related entity type (required)
  final String? mappedBy;            // Field name in target (inverse side)
  final String? foreignKey;          // FK column name (owning side)
  final String referencedColumn;     // Referenced column (default: 'id')
  final bool isOwning;               // Whether this side owns the FK
  final bool cascadeDelete;          // Cascade delete operations
  final bool lazyLoad;               // Load on demand (default: true)
  final bool eagerLoad;              // Load immediately (default: false)
  final bool nullable;               // Whether relationship is nullable
  final bool unique;                 // Enforce uniqueness on FK (default: true)
  final RelationAction onDelete;     // FK constraint action
  final RelationAction onUpdate;     // FK constraint action
}
```

### Example

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

---

## @OneToMany

Defines a one-to-many relationship. This is the owning side - a FK column will be automatically created in the target entity's table as `{ownerEntity}_id`.

### Annotation Reference

```dart
class OneToMany {
  final Type targetEntity;           // Related entity type (required)
  final bool cascadeDelete;          // Cascade delete operations
  final bool lazyLoad;               // Load on demand (default: true)
  final bool eagerLoad;              // Load immediately (default: false)
  final RelationAction onDelete;     // FK constraint action
  final RelationAction onUpdate;     // FK constraint action
}
```

### Example

```dart
// In UserEntity - owns the relationship
// Automatically creates user_entity_id FK column in posts table
@OneToMany(targetEntity: PostEntity)
List<PostEntity>? posts;
```

---

## @ManyToOne

Defines a many-to-one relationship. Use this on the "many" side - this entity will have the foreign key column.

### Annotation Reference

```dart
class ManyToOne {
  final Type targetEntity;           // Related entity type (required)
  final String? foreignKey;          // FK column name (default: {targetEntity}_id)
  final String referencedColumn;     // Referenced column (default: 'id')
  final bool cascadeDelete;          // Cascade delete operations
  final bool lazyLoad;               // Load on demand (default: true)
  final bool eagerLoad;              // Load immediately (default: false)
  final bool nullable;               // Whether relationship is nullable
  final RelationAction onDelete;     // FK constraint action
  final RelationAction onUpdate;     // FK constraint action
}
```

### Example

```dart
// In PostEntity (the "many" side - owning, has FK column)
@ManyToOne(
  targetEntity: UserEntity,
  foreignKey: 'user_id',     // FK column name in posts table
  referencedColumn: 'id',    // Referenced column in users table
  onDelete: RelationAction.cascade,
)
UserEntity? author;
```

---

## @ManyToMany

Creates a junction table to link two entities. One side is the "owning" side (defines the junction table), the other is the "inverse" side.

### Annotation Reference

```dart
class ManyToMany {
  final Type targetEntity;           // Related entity type (required)
  final JoinTable? joinTable;        // Junction table config (owning side)
  final String? mappedBy;            // Field name in target (inverse side)
  final bool cascadeDelete;          // Cascade delete operations
  final bool lazyLoad;               // Load on demand (default: true)
  final bool createIndex;            // Create indexes on junction table
}
```

### JoinTable Configuration

```dart
class JoinTable {
  final String name;                      // Junction table name
  final JoinColumn joinColumn;            // Owning entity's FK column
  final JoinColumn inverseJoinColumn;     // Target entity's FK column
  final List<String>? additionalIndexes;  // Extra indexes
  final List<JunctionColumn>? extraColumns; // Custom columns
}

class JoinColumn {
  final String name;                // Column name in junction table
  final String referencedColumn;    // Referenced column (default: 'id')
  final bool nullable;              // Whether nullable (default: false)
}
```

### Example

```dart
// In UserEntity (owning side - defines junction table)
@ManyToMany(
  targetEntity: RoleEntity,
  joinTable: JoinTable(
    name: 'user_roles',
    joinColumn: JoinColumn(name: 'user_id', referencedColumn: 'id'),
    inverseJoinColumn: JoinColumn(name: 'role_id', referencedColumn: 'id'),
  ),
)
List<RoleEntity>? roles;

// In RoleEntity (inverse side - references owning field)
@ManyToMany(
  targetEntity: UserEntity,
  mappedBy: 'roles',  // Field name in UserEntity
)
List<UserEntity>? users;
```

### Auto-Generated Junction Table

If `joinTable` is not specified, the generator creates one automatically:

```dart
// This will auto-generate junction table "users_role_entity"
@ManyToMany(targetEntity: RoleEntity)
List<RoleEntity>? roles;
```

### Junction Table with Extra Columns

Add custom columns to the junction table:

```dart
@ManyToMany(
  targetEntity: RoleEntity,
  joinTable: JoinTable(
    name: 'user_roles',
    joinColumn: JoinColumn(name: 'user_id'),
    inverseJoinColumn: JoinColumn(name: 'role_id'),
    extraColumns: [
      JunctionColumn(
        name: 'assigned_at',
        type: JunctionColumnType.timestamp,
        defaultValue: 'CURRENT_TIMESTAMP',
      ),
      JunctionColumn(
        name: 'assigned_by',
        type: JunctionColumnType.integer,
        nullable: true,
      ),
      JunctionColumn(
        name: 'is_active',
        type: JunctionColumnType.boolean,
        defaultValue: 'true',
      ),
    ],
  ),
)
List<RoleEntity>? roles;
```

### JunctionColumnType Enum

```dart
enum JunctionColumnType {
  integer, bigint, text, varchar, boolean,
  real, doublePrecision, timestamp, timestamptz,
  date, time, json, jsonb, uuid,
}
```

## Include Syntax

### Basic Include

Load a single relationship:

```dart
// Get blogs with their posts
final blogs = await blogRepo
    .query()
    .include('posts')  // Eager load posts
    .toList();

// Get posts with their parent blog
final posts = await postRepo
    .query()
    .include('blog')   // Eager load blog
    .toList();
```

### Include with Filters

Combine `include()` with WHERE clauses:

```dart
// Get active blogs with their posts
final activeBlogs = await blogRepo
    .query()
    .where('active = @active', {'active': true})
    .include('posts')
    .orderByDescending('created_at')
    .toList();

// Get recent posts with blog info
final recentPosts = await postRepo
    .query()
    .whereNotNull('created_at')
    .whereBetween('created_at', startDate, endDate)
    .include('blog')
    .take(10)
    .toList();
```

### Include with Sorting and Pagination

```dart
// Get top 5 blogs with posts, sorted by title
final topBlogs = await blogRepo
    .query()
    .include('posts')
    .orderBy('title')
    .take(5)
    .toList();

// Paginated posts with blog info
final page2Posts = await postRepo
    .query()
    .include('blog')
    .orderByDescending('created_at')
    .skip(20)
    .take(10)
    .toList();
```

## Code Generation

### Generated Repository with loadRelationships

The code generator creates a `loadRelationships` method for each repository:

```dart
class BlogRepository extends Repository<Blog> {
  BlogRepository() : super('blogs');

  @override
  Future<void> loadRelationships(Blog entity, List<String> includes) async {
    for (final include in includes) {
      switch (include) {
        case 'posts':
          final postRepo = PostRepository();
          postRepo.setConnection(connection);
          final posts = await postRepo
              .query()
              .where('blog_id = @blogId', {'blogId': entity.id})
              .toList();
          // Set entity.posts = posts (requires mutable entity or copyWith)
          break;
        default:
          throw Exception('Unknown relationship: $include');
      }
    }
  }
}
```

## Schema Generation with Foreign Keys

The schema generator automatically detects foreign keys:

```dart
// For a Post entity with blogId field
final postSchema = DatabaseSchema(
  tableName: 'posts',
  columns: [
    ColumnSchema(name: 'id', type: 'INTEGER', primaryKey: true),
    ColumnSchema(name: 'title', type: 'TEXT', nullable: false),
    ColumnSchema(name: 'blog_id', type: 'INTEGER', nullable: false),
    ColumnSchema(name: 'created_at', type: 'TIMESTAMP'),
    // Foreign Keys
    ForeignKey(
      column: 'blog_id',
      referencedTable: 'blogs',
      referencedColumn: 'id'
    ),
  ],
);
```

## Annotations Reference

### @Ignore

Skip a field during code generation:

```dart
@Entity(tableName: 'users')
class User {
  @Column(nullable: false)
  final String name;

  @Ignore()
  final String? temporaryData;  // Not persisted to database
}
```

### @OneToMany

```dart
@OneToMany(
  targetEntity: Post,       // Related entity type
  onDelete: RelationAction.cascade,
)
final List<Post>? posts;
```

### @ManyToOne

```dart
@ManyToOne(
  targetEntity: Blog,       // Parent entity type
  foreignKey: 'blog_id',    // FK column name in this table
  nullable: true,           // Can be null
  onDelete: RelationAction.cascade,  // FK constraint action
)
final Blog? blog;
```

### @ManyToMany

```dart
@ManyToMany(
  targetEntity: Course,           // Related entity type
  joinTableName: 'student_courses', // Join table name
  inverseFieldName: 'students',   // Field name on other side
)
final List<Course>? courses;
```

## Best Practices

### 1. Use Include Sparingly

Only include relationships you need to avoid N+1 queries:

```dart
// Good: Only load what you need
final blogs = await blogRepo.query().include('posts').toList();

// Avoid: Loading unnecessary relationships
final blogs = await blogRepo.query()
    .include('posts')
    .include('author')
    .include('comments')
    .toList();
```

### 2. Foreign Key Naming Convention

Use `{entity}Id` or `{entity}_id` for foreign keys:

```dart
final int blogId;    // Automatically detected as foreign key to 'blogs'
final int authorId;  // Automatically detected as foreign key to 'authors'
```

### 3. Relationship Field Naming

FK column names are auto-derived from the owner entity name:

```dart
class Blog {
  // Automatically creates blog_id FK column in posts table
  @OneToMany(targetEntity: Post)
  final List<Post>? posts;
}

class Post {
  // Optional: define the inverse side with @ManyToOne
  @ManyToOne(targetEntity: Blog, foreignKey: 'blog_id')
  final Blog? blog;
}
```

### 4. Immutable Entities

For immutable entities, consider using a `copyWith` pattern:

```dart
class Blog {
  final int? id;
  final String title;
  final List<Post>? posts;

  const Blog({this.id, required this.title, this.posts});

  Blog copyWith({List<Post>? posts}) {
    return Blog(
      id: this.id,
      title: this.title,
      posts: posts ?? this.posts,
    );
  }
}
```

## Comparison with Entity Framework

| Entity Framework (C#)         | DORM (Dart)                              |
| ----------------------------- | ---------------------------------------- |
| `.Include(b => b.Posts)`      | `.include('posts')`                      |
| `.ThenInclude(p => p.Author)` | Not yet supported                        |
| `[ForeignKey("BlogId")]`      | `foreignKey: 'blog_id'` or auto-detected |
| `[InverseProperty("Blog")]`   | `mappedBy` parameter                     |
| `.AsNoTracking()`             | Default behavior (no change tracking)    |

---

## Generated Repository Methods

### For ManyToMany Relationships

The generator creates dedicated methods for managing ManyToMany relationships:

```dart
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

### Usage

```dart
// Get user with roles
final result = await userRepo.findByIdWithRelations(1, includes: ['roles']);
final user = result!['entity'] as UserEntity;
final roles = result['roles'] as List<RoleEntity>;

// Manage roles
await userRepo.addRole(userId, roleId);
await userRepo.removeRole(userId, roleId);
await userRepo.setRoles(userId, [1, 2, 3]);
await userRepo.clearRoles(userId);

// Get all roles for a user
final userRoles = await userRepo.getRoles(userId);
```

---

## Complete Example

```dart
// user_entity.dart
@Entity(tableName: 'users', dbType: DatabaseType.postgresql)
class UserEntity {
  @Id()
  int? id;

  String name;
  String email;

  // One-to-One: User has one Profile
  @OneToOne(
    targetEntity: ProfileEntity,
    mappedBy: 'user',
  )
  ProfileEntity? profile;

  // One-to-Many: User has many Posts (auto-creates user_entity_id FK in posts table)
  @OneToMany(targetEntity: PostEntity)
  List<PostEntity>? posts;

  // Many-to-Many: User has many Roles
  @ManyToMany(
    targetEntity: RoleEntity,
    joinTable: JoinTable(
      name: 'user_roles',
      joinColumn: JoinColumn(name: 'user_id'),
      inverseJoinColumn: JoinColumn(name: 'role_id'),
    ),
  )
  List<RoleEntity>? roles;

  UserEntity({this.id, required this.name, required this.email});
}

// profile_entity.dart
@Entity(tableName: 'profiles', dbType: DatabaseType.postgresql)
class ProfileEntity {
  @Id()
  int? id;

  String? bio;
  String? avatarUrl;

  // Owning side of One-to-One
  @OneToOne(
    targetEntity: UserEntity,
    foreignKey: 'user_id',
    isOwning: true,
    onDelete: RelationAction.cascade,
  )
  UserEntity? user;

  ProfileEntity({this.id, this.bio, this.avatarUrl});
}

// post_entity.dart
@Entity(tableName: 'posts', dbType: DatabaseType.postgresql)
class PostEntity {
  @Id()
  int? id;

  String title;
  String content;
  int? userId;  // FK column

  // Many-to-One: Post belongs to User (has FK column)
  @ManyToOne(
    targetEntity: UserEntity,
    foreignKey: 'user_id',
    onDelete: RelationAction.cascade,
  )
  UserEntity? author;

  PostEntity({this.id, required this.title, required this.content, this.userId});
}

// role_entity.dart
@Entity(tableName: 'roles', dbType: DatabaseType.postgresql)
class RoleEntity {
  @Id()
  int? id;

  String name;

  // Inverse side of Many-to-Many
  @ManyToMany(
    targetEntity: UserEntity,
    mappedBy: 'roles',
  )
  List<UserEntity>? users;

  RoleEntity({this.id, required this.name});
}
```

---

## Future Enhancements

- **ThenInclude**: Multi-level relationship loading
- **Select with Include**: Project specific fields from related entities
- **Lazy Loading**: Automatic loading when accessing relationship properties
- **Change Tracking**: Track entity modifications for efficient updates
