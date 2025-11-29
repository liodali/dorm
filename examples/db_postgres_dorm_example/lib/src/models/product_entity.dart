import 'package:db_postgres_dorm_example/src/models/user_entity.dart';
import 'package:dorm/dorm.dart';

part 'product_entity.orm.g.dart';

@Entity(tableName: 'products', dbType: DatabaseType.postgresql)
class ProductEntity {
  @Id()
  int? id;

  String name;

  double price;

  @ManyToMany(targetEntity: UserEntity, mappedBy: 'products')
  List<UserEntity>? users;

  ProductEntity({
    this.id,
    required this.name,
    required this.price,
  });
}
