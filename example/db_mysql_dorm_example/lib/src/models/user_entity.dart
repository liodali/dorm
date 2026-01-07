import 'package:db_mysql_dorm_example/src/models/post_entity.dart';
import 'package:db_mysql_dorm_example/src/models/product_entity.dart';
import 'package:dormql/dorm.dart';

part 'user_entity.orm.g.dart';
part 'user_entity.dto.g.dart';

@Entity(
  tableName: 'users',
)
class UserEntity {
  @Id()
  int? id;

  String name;

  String email;

  String? address;
  String? phoneNumber;

  @OneToMany(targetEntity: PostEntity)
  List<PostEntity>? posts;

  @ManyToMany(
    targetEntity: ProductEntity,
    joinTable: JoinTable(
      name: 'user_products',
      joinColumn: JoinColumn(name: 'user_id', referencedColumn: 'id'),
      inverseJoinColumn: JoinColumn(
        name: 'product_id',
        referencedColumn: 'id',
      ),
    ),
  )
  List<ProductEntity>? products;

  UserEntity({
    this.id,
    required this.name,
    required this.email,
    this.address,
    this.phoneNumber,
  });
}
