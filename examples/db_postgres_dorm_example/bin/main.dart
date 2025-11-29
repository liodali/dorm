import 'package:db_postgres_dorm_example/src/db.dart';
import 'package:db_postgres_dorm_example/src/models/user_entity.dart';
import 'package:db_postgres_dorm_example/src/models/post_entity.dart';
import 'package:dorm/dorm.dart';

/// Example migrations for this database
///
/// DORM supports multiple ways to define migrations:
///
/// 1. **RawSqlMigration** - Simple SQL statements
/// 2. **ManualMigration** - Callback-based with full control
/// 3. **CompositeMigration** - Combine multiple migrations
/// 4. **Custom class** - Extend DatabaseMigration for complex logic
final migrations = <DatabaseMigration>[
  // Example 1: Raw SQL migration
  RawSqlMigration(
    version: 3,
    description: 'Add address column to users',
    upSql: "ALTER TABLE users ADD COLUMN IF NOT EXISTS address TEXT;",
    downSql: 'ALTER TABLE users DROP COLUMN IF EXISTS address;',
  ),

  // // Example 3: Manual migration with callback
  // ManualMigration(
  //   version: 3,
  //   description: 'Seed admin user',
  //   onUp: (connection, schemaManager) async {
  //     // Check if admin already exists
  //     final result = await connection.query(
  //       "SELECT id FROM users WHERE email = 'admin@example.com'",
  //     );
  //     if (result.isEmpty) {
  //       await connection.execute(
  //         "INSERT INTO users (name, email) VALUES ('Admin', 'admin@example.com')",
  //       );
  //     }
  //   },
  //   onDown: (connection, schemaManager) async {
  //     await connection.execute(
  //       "DELETE FROM users WHERE email = 'admin@example.com'",
  //     );
  //   },
  // ),

  // // Example 4: Composite migration (multiple steps as one version)
  // CompositeMigration(
  //   version: 4,
  //   description: 'Add audit columns to all tables',
  //   steps: [
  //     RawSqlMigration(
  //       version: 0, // ignored in composite
  //       description: 'Add created_by to users',
  //       upSql: 'ALTER TABLE users ADD COLUMN IF NOT EXISTS created_by INTEGER;',
  //       downSql: 'ALTER TABLE users DROP COLUMN IF EXISTS created_by;',
  //     ),
  //     RawSqlMigration(
  //       version: 0, // ignored in composite
  //       description: 'Add created_by to posts',
  //       upSql: 'ALTER TABLE posts ADD COLUMN IF NOT EXISTS created_by INTEGER;',
  //       downSql: 'ALTER TABLE posts DROP COLUMN IF EXISTS created_by;',
  //     ),
  //   ],
  // ),
];

/// Example usage of DORM with PostgreSQL
void main() async {
  final db = Database();

  try {
    // Setup database: connect (using config from annotation), run migrations, validate schema
    print('Setting up database...');
    await db.setup(
      migrations: migrations,
      validateSchema: true,
    );
    print('Database setup complete!\n');

    // Check migration status
    final appliedVersion = await db.getAppliedMigrationVersion();
    print('Applied migration version: $appliedVersion');
    print(
      'Current migration version: ${DatabaseLifecycle.currentMigrationVersion}',
    );

    final hasPending = await db.hasPendingMigrations(migrations);
    print('Has pending migrations: $hasPending\n');

    // Access schemas from code
    print('Schemas defined in code:');
    for (final schema in db.databaseSchemas) {
      print('  - ${schema.tableName}: ${schema.columns.length} columns');
    }
    print('');

    // Retrieve schemas from database
    print('Schemas from database:');
    final dbSchemas = await db.getAllSchemasFromDatabase();
    for (final schema in dbSchemas) {
      print('  - ${schema.tableName}: ${schema.columns.length} columns');
    }
    print('');

    // Create a user
    print('Creating user...');
    final user = UserEntity(name: 'John Doe', email: 'john@example.com');
    final savedUser = await db.userEntityRepository.save(user);
    print('Created user: ${savedUser.id} - ${savedUser.name}\n');

    // Create posts for the user
    print('Creating posts...');
    final post1 = PostEntity(
      title: 'First Post',
      content: 'This is my first post!',
      userId: savedUser.id,
    );
    final post2 = PostEntity(
      title: 'Second Post',
      content: 'Another great post.',
      userId: savedUser.id,
    );
    await db.postEntityRepository.save(post1);
    await db.postEntityRepository.save(post2);
    print('Created 2 posts\n');

    // Query users
    print('Querying users...');
    final users = await db.userEntityRepository.getAll();
    print('Found ${users.length} users');
    for (final u in users) {
      print('  - ${u.id}: ${u.name} (${u.email})');
    }
    print('');

    // Query posts for user
    print('Querying posts for user ${savedUser.id}...');
    final posts = await db.getPostsByUserId(savedUser.id!);
    print('Found ${posts.length} posts');
    for (final p in posts) {
      print('  - ${p.id}: ${p.title}');
    }
    print('');

    // LINQ-style query example
    print('LINQ-style query example...');
    final recentUsers = await db.userEntityRepository
        .query()
        .where('email LIKE @pattern', {'pattern': '%@example.com'})
        .orderByDescending('id')
        .take(5)
        .toList();
    print('Found ${recentUsers.length} users matching pattern\n');
  } catch (e, stack) {
    print('Error: $e');
    print(stack);
  } finally {
    await db.close();
    print('Database connection closed.');
  }
}
