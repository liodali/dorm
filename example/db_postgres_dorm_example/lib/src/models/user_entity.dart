import 'package:db_postgres_dorm_example/src/models/blog_entity.dart';
import 'package:db_postgres_dorm_example/src/models/post_entity.dart';
import 'package:db_postgres_dorm_example/src/models/purchases_entity.dart';
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

  /// Owning side of ManyToMany - defines the junction table
  // @ManyToMany(
  //   targetEntity: ProductEntity,
  //   joinTable: JoinTable(
  //     name: 'products_users',
  //     joinColumn: JoinColumn(name: 'users_id', referencedColumn: 'id'),
  //     inverseJoinColumn: JoinColumn(
  //       name: 'products_id',
  //       referencedColumn: 'id',
  //     ),
  //   ),
  // )
  // List<ProductEntity>? products;

  /// FK is automatically discovered from PurchasesEntity's @ManyToOne annotation
  @OneToMany(targetEntity: PurchasesEntity)
  List<PurchasesEntity>? purchasesUser;

  /// FK is automatically discovered from BlogEntity's @ManyToOne annotation
  @OneToMany(targetEntity: BlogEntity)
  List<BlogEntity>? blogs;

  /// FK is automatically discovered from PostEntity's @ManyToOne annotation
  @OneToMany(targetEntity: PostEntity)
  List<PostEntity>? posts;

  UserEntity({
    this.id,
    required this.name,
    required this.email,
    this.address,
    this.phoneNumber,
  });
}
