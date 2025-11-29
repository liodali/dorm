import 'package:db_postgres_dorm_example/src/models/blog_entity.dart';
import 'package:dorm/dorm.dart';

part 'user_entity.orm.g.dart';

@Entity(
  tableName: 'users',
  dbType: DatabaseType.postgresql,
)
class UserEntity {
  @Id()
  int? id;

  String name;

  String email;

  @OneToMany(targetEntity: BlogEntity, mappedBy: 'user')
  List<BlogEntity>? blogs;

  UserEntity({this.id, required this.name, required this.email});
}
