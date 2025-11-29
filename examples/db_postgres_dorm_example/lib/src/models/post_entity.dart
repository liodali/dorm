import 'package:dorm/dorm.dart';

part 'post_entity.orm.g.dart';
@Entity(tableName: 'posts', dbType: DatabaseType.postgresql)
class PostEntity {
  @Id()
  int? id;

  String title;

  String content;

  int? userId;

  PostEntity({
    this.id,
    required this.title,
    required this.content,
    this.userId,
  });
}
