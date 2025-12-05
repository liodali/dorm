import 'package:db_postgres_dorm_example/src/models/product_entity.dart';
import 'package:db_postgres_dorm_example/src/models/user_entity.dart';
import 'package:dormql/dorm.dart';

@Entity(tableName: 'purchases')
class PurchasesEntity {
  @Id(autoIncrement: true)
  int? id;

  @Unique()
  String uuid;
  @Column(name: 'amount')
  double amount;
  @Column(name: 'voucher_code')
  String? voucherCode;
  @Column(name: 'createdAt')
  int createdAt;

  @Column(name: 'user_id')
  int userId;

  @ManyToMany(
    targetEntity: ProductEntity,
    joinTable: JoinTable(
      name: 'purchases_products',
      joinColumn: JoinColumn(name: 'purchase_id'),
      inverseJoinColumn: JoinColumn(name: 'product_id'),
    ),
  )
  List<ProductEntity>? products;

  @ManyToOne(targetEntity: UserEntity, foreignKey: 'user_id')
  UserEntity? user;

  PurchasesEntity({
    this.id,
    required this.uuid,
    required this.amount,
    this.voucherCode,
    required this.userId,
    required this.createdAt,
  });
}
