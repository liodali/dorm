import 'package:dorm/dorm.dart';

/// Example demonstrating column name mapping
///
/// Rules:
/// 1. If @Column(name: 'custom_name') is specified, use that name
/// 2. Otherwise, convert camelCase field names to snake_case
/// 3. Field names already in snake_case remain unchanged

@Entity(tableName: 'users', dbType: DatabaseType.postgresql)
class User {
  // Primary key - auto-converted to 'id'
  @Id(autoIncrement: true)
  final int? id;

  // Simple field - auto-converted to 'first_name'
  @Column(nullable: false)
  final String firstName;

  // Simple field - auto-converted to 'last_name'
  @Column(nullable: false)
  final String lastName;

  // Custom column name specified
  @Column(name: 'user_email', nullable: false, unique: true)
  final String email;

  // Complex camelCase - auto-converted to 'date_of_birth'
  @Column(nullable: true)
  final DateTime? dateOfBirth;

  // Already snake_case - remains 'phone_number'
  @Column(nullable: true)
  final String? phone_number;

  // Custom name different from field name
  @Column(name: 'account_status', nullable: false)
  final String status;

  // Auto-converted to 'created_at'
  @Column(nullable: true)
  final DateTime? createdAt;

  // Auto-converted to 'updated_at'
  @Column(nullable: true)
  final DateTime? updatedAt;

  // Ignored field - not in database
  @Ignore()
  final String? temporaryToken;

  const User({
    this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.dateOfBirth,
    this.phone_number,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.temporaryToken,
  });
}

/// Generated repository will look like this:
///
/// ```dart
/// class UserRepository extends Repository<User> {
///   UserRepository() : super('users');
///
///   @override
///   User fromRow(Map<String, dynamic> row) {
///     return User(
///       id: row['id'] as int?,
///       firstName: row['first_name'] as String,
///       lastName: row['last_name'] as String,
///       email: row['user_email'] as String,  // Custom name
///       dateOfBirth: row['date_of_birth'] != null
///           ? DateTime.parse(row['date_of_birth'] as String)
///           : null,
///       phone_number: row['phone_number'] as String?,
///       status: row['account_status'] as String,  // Custom name
///       createdAt: row['created_at'] != null
///           ? DateTime.parse(row['created_at'] as String)
///           : null,
///       updatedAt: row['updated_at'] != null
///           ? DateTime.parse(row['updated_at'] as String)
///           : null,
///     );
///   }
///
///   @override
///   Map<String, dynamic> toRow(User entity) {
///     return {
///       'id': entity.id,
///       'first_name': entity.firstName,
///       'last_name': entity.lastName,
///       'user_email': entity.email,  // Custom name
///       'date_of_birth': entity.dateOfBirth?.toIso8601String(),
///       'phone_number': entity.phone_number,
///       'account_status': entity.status,  // Custom name
///       'created_at': entity.createdAt?.toIso8601String(),
///       'updated_at': entity.updatedAt?.toIso8601String(),
///     };
///   }
/// }
/// ```

@Entity(tableName: 'products', dbType: DatabaseType.postgresql)
class Product {
  @Id(autoIncrement: true)
  final int? id;

  // Auto-converted: productName -> product_name
  @Column(nullable: false)
  final String productName;

  // Auto-converted: productCode -> product_code
  @Column(nullable: false, unique: true)
  final String productCode;

  // Custom name
  @Column(name: 'unit_price', nullable: false)
  final double price;

  // Auto-converted: stockQuantity -> stock_quantity
  @Column(nullable: false)
  final int stockQuantity;

  // Auto-converted: categoryId -> category_id (foreign key)
  @Column(nullable: false)
  final int categoryId;

  // Relationship - not a column
  @OneToMany(
    targetEntity: Category,
    foreignKey: 'category_id',
    isOwning: true,
    eagerLoad: false,
  )
  final Category? category;

  const Product({
    this.id,
    required this.productName,
    required this.productCode,
    required this.price,
    required this.stockQuantity,
    required this.categoryId,
    this.category,
  });
}

@Entity(tableName: 'categories', dbType: DatabaseType.postgresql)
class Category {
  @Id(autoIncrement: true)
  final int? id;

  // Auto-converted: categoryName -> category_name
  @Column(nullable: false)
  final String categoryName;

  // Custom name
  @Column(name: 'description', nullable: true)
  final String? categoryDescription;

  // Relationship
  @OneToMany(targetEntity: Product, mappedBy: 'categoryId')
  final List<Product>? products;

  const Category({
    this.id,
    required this.categoryName,
    this.categoryDescription,
    this.products,
  });
}

void main() async {
  print('Column Mapping Examples:');
  print('');
  print('Field Name          → Column Name');
  print('─────────────────────────────────────');
  print('firstName           → first_name');
  print('lastName            → last_name');
  print('email (custom)      → user_email');
  print('dateOfBirth         → date_of_birth');
  print('phone_number        → phone_number');
  print('status (custom)     → account_status');
  print('createdAt           → created_at');
  print('updatedAt           → updated_at');
  print('');
  print('productName         → product_name');
  print('productCode         → product_code');
  print('price (custom)      → unit_price');
  print('stockQuantity       → stock_quantity');
  print('categoryId          → category_id');
  print('');
  print('Rules:');
  print('1. @Column(name: "custom") → use custom name');
  print('2. camelCase → snake_case');
  print('3. snake_case → unchanged');
  print('4. @Ignore() → not in database');
  print('5. Relationships → not columns');
}

/// SQL Schema generated for User table:
/// 
/// CREATE TABLE users (
///   id SERIAL PRIMARY KEY,
///   first_name VARCHAR(255) NOT NULL,
///   last_name VARCHAR(255) NOT NULL,
///   user_email VARCHAR(255) NOT NULL UNIQUE,
///   date_of_birth TIMESTAMP,
///   phone_number VARCHAR(255),
///   account_status VARCHAR(255) NOT NULL,
///   created_at TIMESTAMP,
///   updated_at TIMESTAMP
/// );

/// SQL Schema generated for Product table:
/// 
/// CREATE TABLE products (
///   id SERIAL PRIMARY KEY,
///   product_name VARCHAR(255) NOT NULL,
///   product_code VARCHAR(255) NOT NULL UNIQUE,
///   unit_price DOUBLE PRECISION NOT NULL,
///   stock_quantity INTEGER NOT NULL,
///   category_id INTEGER NOT NULL,
///   FOREIGN KEY (category_id) REFERENCES categories(id)
/// );

/// SQL Schema generated for Category table:
/// 
/// CREATE TABLE categories (
///   id SERIAL PRIMARY KEY,
///   category_name VARCHAR(255) NOT NULL,
///   description TEXT
/// );
