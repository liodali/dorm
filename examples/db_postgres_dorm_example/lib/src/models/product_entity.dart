import 'package:db_postgres_dorm_example/src/models/user_entity.dart';
import 'package:dorm/dorm.dart';

part 'product_entity.orm.g.dart';

@Entity(tableName: 'products', dbType: DatabaseType.postgresql)
class ProductEntity {
  @Id()
  int? id;

  String name;

  double price;

  /// Owning side of ManyToMany - defines the junction table
  @ManyToMany(
    targetEntity: UserEntity,
    joinTable: JoinTable(
      name: 'products_users',
      joinColumn: JoinColumn(name: 'products_id', referencedColumn: 'id'),
      inverseJoinColumn: JoinColumn(name: 'users_id', referencedColumn: 'id'),
    ),
  )
  List<UserEntity>? users;

  ProductEntity({
    this.id,
    required this.name,
    required this.price,
  });
}
