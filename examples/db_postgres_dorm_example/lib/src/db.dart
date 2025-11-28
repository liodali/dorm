import 'package:db_postgres_dorm_example/src/models/post_entity.dart';
import 'package:dorm/dorm.dart';

import 'models/user_entity.dart';

part 'db.db.g.dart';

@Db(
  entities: [UserEntity, PostEntity],
  migrationVersion: 1,
  dbType: DatabaseType.postgresql,
  name: 'mydb',
)
class Database {
  final DatabaseConfig config;
  DatabaseConnection? _connection;

  Database()
    : config = DatabaseConfig.postgresql(
        host: 'localhost',
        port: 5432,
        database: 'mydb',
        username: 'user',
        password: 'password',
      );

  /// Get the database connection
  DatabaseConnection? get connection => _connection;

  Future<void> init() async {
    _connection ??= await DatabaseFactory.createConnection(config);
  }

  Future<UserEntity?> getUserById(int id) async {
    return userEntityRepository.findById(id);
  }

  Future<void> close() async {
    await _connection?.close();
    _connection = null;
  }
}
