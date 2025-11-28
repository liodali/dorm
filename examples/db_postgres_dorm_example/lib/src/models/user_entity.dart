import 'package:dorm/dorm.dart';

part 'user_entity.orm.g.dart';

@Entity(tableName: 'users', dbType: DatabaseType.postgresql)
class UserEntity {
  @Id()
  int? id;

  String name;

  String email;

  UserEntity({this.id, required this.name, required this.email});
}
