import 'package:db_postgres_dorm_example/src/models/user_entity.dart';
import 'package:dorm/dorm.dart';

part 'blog_entity.orm.g.dart';
part 'blog_entity.schema.g.dart';

@Entity(tableName: 'blogs', dbType: DatabaseType.postgresql)
class BlogEntity {
  @Id()
  int? id;

  String title;

  String content;

  int? createdAt;

  int? modifiedAt;

  int? userId;

  @OneToMany(targetEntity: UserEntity, foreignKey: 'user_id', isOwning: true)
  UserEntity? user;

  BlogEntity({
    this.id,
    required this.title,
    required this.content,
    this.userId,
  });
}
