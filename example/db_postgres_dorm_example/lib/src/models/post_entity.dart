import 'package:db_postgres_dorm_example/src/models/user_entity.dart';
import 'package:dormql/dorm.dart';

part 'post_entity.orm.g.dart';

@Entity(tableName: 'posts', dbType: DatabaseType.postgresql)
class PostEntity {
  @Id()
  int? id;

  String title;

  String content;

  int? userId;

  @ManyToOne(targetEntity: UserEntity, foreignKey: 'user_id')
  UserEntity? user;

  PostEntity({
    this.id,
    required this.title,
    required this.content,
    this.userId,
  });
}
