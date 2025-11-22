# DORM Relationships & Include Syntax

## Overview

DORM supports Entity Framework-style relationship loading with the `include()` method, allowing you to eager load related entities in LINQ-style queries.

## Relationship Types

### 1. OneToMany

A parent entity has multiple child entities.

```dart
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

### 2. ManyToOne

A child entity belongs to a parent entity.

```dart
@Entity(tableName: 'posts')
class Post {
  @Id(autoIncrement: true)
  final int? id;

  @Column(nullable: false)
  final String title;

  @Column(nullable: false)
  final int blogId;  // Foreign key

  @ManyToOne(targetEntity: Blog, eagerLoad: false)
  final Blog? blog;

  const Post({
    this.id,
    required this.title,
    required this.blogId,
    this.blog
  });
}
```

### 3. ManyToMany

Multiple entities on both sides (requires join table).

```dart
@Entity(tableName: 'students')
class Student {
  @Id(autoIncrement: true)
  final int? id;

  @Column(nullable: false)
  final String name;

  @ManyToMany(
    targetEntity: Course,
    joinTableName: 'student_courses',
    inverseFieldName: 'students',
  )
  final List<Course>? courses;
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
  mappedBy: 'blogId',       // Foreign key field in target entity
  cascadeDelete: false,     // Delete related entities on parent delete
  lazyLoad: true,           // Load on demand (default)
)
final List<Post>? posts;
```

### @ManyToOne

```dart
@ManyToOne(
  targetEntity: Blog,       // Parent entity type
  nullable: true,           // Can be null
  cascadeDelete: false,     // Delete this entity when parent is deleted
  eagerLoad: false,         // Load immediately with parent (default: false)
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

Match the `mappedBy` parameter to the foreign key field:

```dart
class Blog {
  @OneToMany(targetEntity: Post, mappedBy: 'blogId')
  final List<Post>? posts;
}

class Post {
  final int blogId;  // Must match mappedBy value

  @ManyToOne(targetEntity: Blog)
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

| Entity Framework (C#)         | DORM (Dart)                           |
| ----------------------------- | ------------------------------------- |
| `.Include(b => b.Posts)`      | `.include('posts')`                   |
| `.ThenInclude(p => p.Author)` | Not yet supported                     |
| `[ForeignKey("BlogId")]`      | Auto-detected by naming convention    |
| `[InverseProperty("Blog")]`   | `mappedBy` parameter                  |
| `.AsNoTracking()`             | Default behavior (no change tracking) |

## Future Enhancements

- **ThenInclude**: Multi-level relationship loading
- **Select with Include**: Project specific fields from related entities
- **Lazy Loading**: Automatic loading when accessing relationship properties
- **Change Tracking**: Track entity modifications for efficient updates
