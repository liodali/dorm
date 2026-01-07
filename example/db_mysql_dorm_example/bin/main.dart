import 'package:db_mysql_dorm_example/src/db.dart';
import 'package:db_mysql_dorm_example/src/models/product_entity.dart';
import 'package:db_mysql_dorm_example/src/models/user_entity.dart';
import 'package:db_mysql_dorm_example/src/models/post_entity.dart';
import 'package:dormql/dorm.dart';

final migrations = <DatabaseMigration>[
  RawSqlMigration(
    version: 3,
    description: 'Add address column to users',
    upSql: 'ALTER TABLE users ADD COLUMN IF NOT EXISTS address TEXT;',
    downSql: 'ALTER TABLE users DROP COLUMN IF EXISTS address;',
  ),
  ManualMigration(
    version: 4,
    description: 'Seed initial data',
    onUp: (connection, schemaManager) async {},
    onDown: (connection, schemaManager) async {},
  ),
  RawSqlMigration(
    version: 5,
    description: 'Add phone_number column to users',
    upSql: 'ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_number TEXT;',
    downSql: 'ALTER TABLE users DROP COLUMN IF EXISTS phone_number;',
  ),
];

void main() async {
  final db = Database();

  try {
    print('Setting up MySQL database...');
    await db.setup(customMigrations: migrations);
    print('Database setup complete!\n');

    final appliedVersion = await db.getAppliedMigrationVersion();
    print('Applied migration version: $appliedVersion');
    print(
      'Current migration version: ${DatabaseLifecycle.currentMigrationVersion}',
    );

    final hasPending = await db.hasPendingMigrations(migrations);
    print('Has pending migrations: $hasPending\n');

    print('Schemas defined in code:');
    for (final schema in db.databaseSchemas) {
      print('  - ${schema.tableName}: ${schema.columns.length} columns');
    }
    print('');

    print('Schemas from database:');
    final dbSchemas = await db.getAllSchemasFromDatabase();
    for (final schema in dbSchemas) {
      print('  - ${schema.tableName}: ${schema.columns.length} columns');
    }
    print('');

    print('Creating user...');
    final user = UserEntity(
      name: 'Jane Smith',
      email: 'jane@example.com',
      address: '456 Oak Avenue, MySQL City',
    );
    final savedUser = await db.userEntityRepository.save(user);
    print('Created user: ${savedUser.id} - ${savedUser.name}\n');

    print('Creating posts...');
    final post1 = PostEntity(
      title: 'MySQL with DormQL',
      content: 'This is a post using MySQL database!',
      userId: savedUser.id,
    );
    final post2 = PostEntity(
      title: 'Second MySQL Post',
      content: 'Another post in MySQL.',
      userId: savedUser.id,
    );
    await db.postEntityRepository.save(post1);
    await db.postEntityRepository.save(post2);
    print('Created 2 posts\n');

    print('Creating products...');
    final product1 = ProductEntity(
      name: 'MySQL Product 1',
      description: 'First product in MySQL',
      category: 'Electronics',
      price: 299.99,
    );
    final product2 = ProductEntity(
      name: 'MySQL Product 2',
      description: 'Second product in MySQL',
      category: 'Books',
      price: 19.99,
    );
    final product1Saved = await db.productEntityRepository.save(product1);
    final product2Saved = await db.productEntityRepository.save(product2);
    print('Created 2 products\n');

    print('Linking products to user...');
    await db.userEntityRepository.addProduct(savedUser.id!, product1Saved.id!);
    await db.userEntityRepository.addProduct(savedUser.id!, product2Saved.id!);
    print('Linked products to user\n');

    final userProducts = await db.userEntityRepository.getProducts(
      savedUser.id!,
    );
    print('Products for user: ${userProducts.length}');
    for (final p in userProducts) {
      print('  - ${p.id}: ${p.name} - \$${p.price}');
    }
    print('');

    print('Querying users...');
    final users = await db.userEntityRepository.getAll();
    print('Found ${users.length} users');
    for (final u in users) {
      print('  - ${u.id}: ${u.name} (${u.email})');
    }
    print('');

    print('Querying posts for user ${savedUser.id}...');
    final posts = await db.getPostsByUserId(savedUser.id!);
    print('Found ${posts.length} posts');
    for (final p in posts) {
      print('  - ${p.id}: ${p.title}');
    }
    print('');

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
