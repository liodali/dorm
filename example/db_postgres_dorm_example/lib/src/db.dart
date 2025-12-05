import 'package:db_postgres_dorm_example/src/models/blog_entity.dart';
import 'package:db_postgres_dorm_example/src/models/post_entity.dart';
import 'package:db_postgres_dorm_example/src/models/product_entity.dart';
import 'package:dormql/dorm.dart';

import 'models/user_entity.dart';

part 'db.schemas.g.dart';
part 'db.db.g.dart';
part 'db.migration.g.dart';

@Db(
  entities: [UserEntity, PostEntity, BlogEntity, ProductEntity],
  migrationVersion: 8,
  config: DbConfig.postgresql(
    host: 'localhost',
    port: 5432,
    database: 'mydb',
    username: 'postgres',
    password: 'postgres',
  ),
  name: 'mydb',
  generateSql: true, // Generates SQL file at .dart_tool/dorm/mydb.sql
  sqlDialect:
      DatabaseType.postgresql, // Specify PostgreSQL dialect for SQL generation
)
class Database {
  /// Database connection (managed by generated code)
  DatabaseConnection? _connection;

  /// Get the database connection
  DatabaseConnection? get connection => _connection;

  /// Get a user by ID
  Future<UserEntity?> getUserById(int id) async {
    return userEntityRepository.findById(id);
  }

  /// Get a user by ID
  Future<UserEntity?> getUserWithPostsById(int id) async {
    return userEntityRepository.findById(id);
  }

  /// Get all posts for a user
  Future<List<PostEntity>> getPostsByUserId(int userId) async {
    return postEntityRepository.query().where('user_id = @userId', {
      'userId': userId,
    }).toList();
  }
}
