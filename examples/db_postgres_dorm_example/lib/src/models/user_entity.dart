import 'package:db_postgres_dorm_example/src/models/blog_entity.dart';
import 'package:db_postgres_dorm_example/src/models/post_entity.dart';
import 'package:db_postgres_dorm_example/src/models/product_entity.dart';
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

  String? address;

  /// Inverse side of ManyToMany - references the owning side field
  @ManyToMany(targetEntity: ProductEntity, mappedBy: 'users')
  List<ProductEntity>? products;

  @OneToMany(targetEntity: BlogEntity, mappedBy: 'user')
  List<BlogEntity>? blogs;
  @OneToMany(targetEntity: PostEntity, mappedBy: 'user')
  List<PostEntity>? posts;

  UserEntity({
    this.id,
    required this.name,
    required this.email,
    this.address,
  });
}
