import 'package:db_mysql_dorm_example/src/models/post_entity.dart';
import 'package:db_mysql_dorm_example/src/models/product_entity.dart';
import 'package:dormql/dorm.dart';

import 'models/user_entity.dart';

part 'db.schemas.g.dart';
part 'db.db.g.dart';
part 'db.migration.g.dart';

@Db(
  entities: [UserEntity, PostEntity, ProductEntity],
  migrationVersion: 5,
  config: DbConfig.mysql(
    host: 'localhost',
    port: 3306,
    database: 'mydb',
    username: 'root',
    password: 'rootpassword',
  ),
  name: 'mydb',
  generateSql: true,
  sqlDialect: DatabaseType.mysql,
)
class Database {
  DatabaseConnection? _connection;

  DatabaseConnection? get connection => _connection;

  Future<UserEntity?> getUserById(int id) async {
    return userEntityRepository.findById(id);
  }

  Future<List<PostEntity>> getPostsByUserId(int userId) async {
    return postEntityRepository.query().where('user_id = @userId', {
      'userId': userId,
    }).toList();
  }
}
