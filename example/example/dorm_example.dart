import 'package:dartorm/dorm.dart';

/// Example entity class
@Entity(tableName: 'users', dbType: DatabaseType.postgresql)
class User {
  @Id(autoIncrement: true)
  final int? id;

  @Column(nullable: false)
  final String name;

  @Column(nullable: false)
  final String email;

  @Column(nullable: true)
  final DateTime? createdAt;

  @Ignore()
  final String? temporaryData;

  const User({
    this.id,
    required this.name,
    required this.email,
    this.createdAt,
    this.temporaryData,
  });
}

/// User repository (would be generated)
class UserRepository extends Repository<User> {
  UserRepository() : super('users');

  @override
  User fromRow(Map<String, dynamic> row) {
    return User(
      id: row['id'] as int?,
      name: row['name'] as String,
      email: row['email'] as String,
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : null,
    );
  }

  @override
  Map<String, dynamic> toRow(User entity) {
    return {
      'id': entity.id,
      'name': entity.name,
      'email': entity.email,
      'created_at': entity.createdAt?.toIso8601String(),
    };
  }
}

void main() async {
  // Configure database connection
  final config = DatabaseConfig.postgresql(
    host: 'localhost',
    port: 5432,
    database: 'mydb',
    username: 'user',
    password: 'password',
  );

  // Create connection
  final connection = await DatabaseFactory.createConnection(config);

  // Initialize repository
  final userRepo = UserRepository();
  userRepo.setConnection(connection);

  try {
    // LINQ-style queries
    print('\n=== LINQ-Style Query Examples ===');

    // Get all users
    final allUsers = await userRepo.getAll();
    print('All users: ${allUsers.length}');

    // Find by ID
    final user = await userRepo.findById(1);
    print('User by ID: ${user?.name}');

    // Complex query with WHERE, ORDER BY, LIMIT
    final activeUsers = await userRepo
        .query()
        .where('email LIKE @pattern', {'pattern': '%@example.com'})
        .orderByDescending('created_at')
        .take(10)
        .toList();
    print('Active users: ${activeUsers.length}');

    // Query with multiple conditions
    final recentUsers = await userRepo
        .query()
        .whereNotNull('created_at')
        .whereBetween('id', 1, 100)
        .orderBy('name')
        .toList();
    print('Recent users: ${recentUsers.length}');

    // Count query
    final count = await userRepo.query().countSql();
    print('Total users: $count');

    // Check if any records exist
    final hasUsers = await userRepo.query().where('email = @email', {
      'email': 'test@example.com',
    }).any();
    print('Has test user: $hasUsers');

    // Aggregate functions
    final maxId = await userRepo.query().max('id');
    print('Max user ID: $maxId');

    final minId = await userRepo.query().min('id');
    print('Min user ID: $minId');

    final avgId = await userRepo.query().avg('id');
    print('Average user ID: $avgId');

    final sumIds = await userRepo.query().sum('id');
    print('Sum of user IDs: $sumIds');

    // Save new user
    print('\n=== Save Example ===');
    final newUser = User(
      name: 'John Doe',
      email: 'john@example.com',
      createdAt: DateTime.now(),
    );
    // final savedUser = await userRepo.save(newUser);
    // print('Saved user ID: ${savedUser.id}');

    // Raw SQL query
    print('\n=== Raw SQL Example ===');
    final rawQuery = userRepo.executeRawQuery(
      'SELECT * FROM users WHERE email = @email',
      {'email': 'john@example.com'},
    );
    final rawResults = await rawQuery.execute();
    print('Raw query results: ${rawResults.length}');

    // Stored procedure
    print('\n=== Stored Procedure Example ===');
    final proc = userRepo.executeProcedure(
      'get_user_stats',
      parameters: [2024],
    );
    // final procResults = await proc.Execute();
    // print('Procedure results: ${procResults.length}');

    // Transaction example
    print('\n=== Transaction Example ===');
    final transaction = await connection.beginTransaction();
    try {
      await transaction.execute(
        'INSERT INTO users (name, email) VALUES (@name, @email)',
        parameters: {'name': 'Jane Doe', 'email': 'jane@example.com'},
      );
      await transaction.commit();
      print('Transaction committed');
    } catch (e) {
      await transaction.rollback();
      print('Transaction rolled back: $e');
    }

    print('\n=== Connection Pool Example ===');
    final pool = await DatabaseFactory.createPool(config, maxConnections: 5);
    final poolConn = await pool.getConnection();
    print('Pool stats: ${pool.stats}');
    await pool.releaseConnection(poolConn);
    await pool.close();
  } finally {
    // Close connection
    await connection.close();
    print('\nConnection closed');
  }

  print('\n=== DORM Example Complete ===');
}
