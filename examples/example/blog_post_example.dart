import 'package:dorm/dorm.dart';

/// Blog entity with OneToMany relationship to Posts
@Entity(tableName: 'blogs', dbType: DatabaseType.postgresql)
class Blog {
  @Id(autoIncrement: true)
  final int? id;

  @Column(nullable: false)
  final String title;

  @Column(nullable: true)
  final String? description;

  @Column(nullable: true)
  final DateTime? createdAt;

  @OneToMany(targetEntity: Post)
  final List<Post>? posts;

  const Blog({
    this.id,
    required this.title,
    this.description,
    this.createdAt,
    this.posts,
  });
}

/// Post entity with ManyToOne relationship to Blog
@Entity(tableName: 'posts', dbType: DatabaseType.postgresql)
class Post {
  @Id(autoIncrement: true)
  final int? id;

  @Column(nullable: false)
  final String title;

  @Column(nullable: false)
  final String content;

  @Column(nullable: false)
  final int blogId;

  @Column(nullable: true)
  final DateTime? createdAt;

  @ManyToOne(
    targetEntity: Blog,
    foreignKey: 'blog_id',
  )
  final Blog? blog;

  const Post({
    this.id,
    required this.title,
    required this.content,
    required this.blogId,
    this.createdAt,
    this.blog,
  });
}

/// Blog repository (generated code example)
class BlogRepository extends Repository<Blog> {
  BlogRepository() : super('blogs');

  @override
  Blog fromRow(Map<String, dynamic> row) {
    return Blog(
      id: row['id'] as int?,
      title: row['title'] as String,
      description: row['description'] as String?,
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : null,
    );
  }

  @override
  Map<String, dynamic> toRow(Blog entity) {
    return {
      'id': entity.id,
      'title': entity.title,
      'description': entity.description,
      'created_at': entity.createdAt?.toIso8601String(),
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
          final posts = await postRepo.query().where('blog_id = @blogId', {
            'blogId': entity.id,
          }).toList();
          // In real implementation, you would set this on a mutable entity
          // or use a different pattern like copyWith
          break;
        default:
          throw Exception('Unknown relationship: $include');
      }
    }
  }
}

/// Post repository (generated code example)
class PostRepository extends Repository<Post> {
  PostRepository() : super('posts');

  @override
  Post fromRow(Map<String, dynamic> row) {
    return Post(
      id: row['id'] as int?,
      title: row['title'] as String,
      content: row['content'] as String,
      blogId: row['blog_id'] as int,
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : null,
    );
  }

  @override
  Map<String, dynamic> toRow(Post entity) {
    return {
      'id': entity.id,
      'title': entity.title,
      'content': entity.content,
      'blog_id': entity.blogId,
      'created_at': entity.createdAt?.toIso8601String(),
    };
  }

  @override
  Future<void> loadRelationships(Post entity, List<String> includes) async {
    for (final include in includes) {
      switch (include) {
        case 'blog':
          // Load ManyToOne relationship for blog
          final blogRepo = BlogRepository();
          blogRepo.setConnection(connection);
          final blog = await blogRepo.findById(entity.blogId);
          // In real implementation, set this on the entity
          break;
        default:
          throw Exception('Unknown relationship: $include');
      }
    }
  }
}

void main() async {
  // Configure database connection
  final config = DatabaseConfig.postgresql(
    host: 'localhost',
    port: 5432,
    database: 'mydb',
    username: 'user',
    password: 'password',
  );

  // Create connection
  final connection = await DatabaseFactory.createConnection(config);

  // Initialize repositories
  final blogRepo = BlogRepository();
  blogRepo.setConnection(connection);

  final postRepo = PostRepository();
  postRepo.setConnection(connection);

  try {
    print('\n=== LINQ-Style Include Examples ===');

    // Example 1: Get all blogs with their posts (eager loading)
    // blogs.include(b => b.posts)
    final blogsWithPosts = await blogRepo
        .query()
        .include('posts') // This will eager load the posts relationship
        .toList();
    print('Loaded ${blogsWithPosts.length} blogs with posts');

    // Example 2: Get specific blog with posts
    final blog = await blogRepo
        .query()
        .where('id = @id', {'id': 1})
        .include('posts')
        .firstOrDefault();
    print('Blog: ${blog?.title}');
    print('Posts count: ${blog?.posts?.length ?? 0}');

    // Example 3: Get posts with their parent blog
    // posts.include(p => p.blog)
    final postsWithBlog = await postRepo
        .query()
        .include('blog') // This will eager load the blog relationship
        .orderByDescending('created_at')
        .take(10)
        .toList();
    print('Loaded ${postsWithBlog.length} posts with blog info');

    // Example 4: Complex query with include and filters
    final recentPosts = await postRepo
        .query()
        .whereNotNull('created_at')
        .whereLike('title', '%tutorial%')
        .include('blog')
        .orderByDescending('created_at')
        .take(5)
        .toList();
    print('Recent tutorial posts: ${recentPosts.length}');

    // Example 5: Multiple includes (if supported)
    // In Entity Framework: query.Include(b => b.posts).ThenInclude(p => p.comments)
    // For now, we support single level includes
    final blogsWithDetails = await blogRepo
        .query()
        .where('created_at > @date', {
          'date': DateTime(2024, 1, 1).toIso8601String(),
        })
        .include('posts')
        .toList();
    print('Blogs with details: ${blogsWithDetails.length}');

    print('\n=== Schema Information ===');
    print('Blogs table: blogs');
    print('Posts table: posts');
    print('Relationship: Blog (1) -> Posts (Many)');
    print('Foreign Key: posts.blog_id -> blogs.id');
  } finally {
    await connection.close();
    print('\nConnection closed');
  }

  print('\n=== Blog/Post Example Complete ===');
}
