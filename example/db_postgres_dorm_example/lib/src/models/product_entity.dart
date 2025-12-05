import 'package:db_postgres_dorm_example/src/models/purchases_entity.dart';
import 'package:dormql/dorm.dart';

part 'product_entity.orm.g.dart';

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

  // /// Inverse side of ManyToMany - references the owning side field
  // @ManyToMany(targetEntity: UserEntity, mappedBy: 'products')
  // List<UserEntity>? users;

  /// Inverse side of ManyToMany - references the owning side field
  @ManyToMany(targetEntity: PurchasesEntity, mappedBy: 'products')
  List<PurchasesEntity>? purchases;

  ProductEntity({
    this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.price,
  });
}
