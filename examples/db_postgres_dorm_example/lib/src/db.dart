import 'package:db_postgres_dorm_example/src/models/blog_entity.dart';
import 'package:db_postgres_dorm_example/src/models/post_entity.dart';
import 'package:dorm/dorm.dart';

import 'models/user_entity.dart';

part 'db.db.g.dart';

@Db(
  entities: [UserEntity, PostEntity, BlogEntity],
  migrationVersion: 2,
  config: DbConfig.postgresql(
    host: 'localhost',
    port: 5432,
    database: 'mydb',
    username: 'user',
    password: 'password',
  ),
  name: 'mydb',
  generateSql: true, // Generates SQL file at .dart_tool/dorm/mydb.sql
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

  /// Get all posts for a user
  Future<List<PostEntity>> getPostsByUserId(int userId) async {
    return postEntityRepository.query().where('user_id = @userId', {
      'userId': userId,
    }).toList();
  }
}
