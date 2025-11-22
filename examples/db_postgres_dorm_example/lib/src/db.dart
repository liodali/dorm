import 'package:db_postgres_dorm_example/src/models/user_entity.dart';
import 'package:dorm/dorm.dart';
import 'package:db_postgres_dorm_example/src/models/user_entity.orm.g.dart';

class Database {
  final DatabaseConfig config;
  DatabaseConnection? _connection;

  final UserEntityRepository userRepo;
  Database()
    : config = DatabaseConfig.postgresql(
        host: 'localhost',
        port: 5432,
        database: 'mydb',
        username: 'user',
        password: 'password',
      ),
      userRepo = UserEntityRepository();

  Future<void> init() async {
    _connection ??= await DatabaseFactory.createConnection(config);
  }

  Future<UserEntity?> getUserById(int id) async {
    return userRepo.findById(id);
  }

  Future<void> close() async {
    _connection?.close();
    _connection = null;
  }
}
