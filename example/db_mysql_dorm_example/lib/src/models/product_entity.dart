import 'package:db_mysql_dorm_example/src/models/user_entity.dart';
import 'package:dormql/dorm.dart';

part 'product_entity.orm.g.dart';
part 'product_entity.dto.g.dart';

@Entity(tableName: 'products')
class ProductEntity {
  @Id()
  int? id;

  @Column()
  String name;

  @Column()
  String description;

  @Column()
  String category;

  @Column()
  double price;

  @ManyToMany(targetEntity: UserEntity, mappedBy: 'products')
  List<UserEntity>? users;

  ProductEntity({
    this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.price,
  });
}
