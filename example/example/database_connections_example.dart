import 'package:dartorm/dorm.dart';

/// Example demonstrating all three database connection types

void main() async {
  print('=== DORM Database Connections Example ===\n');

  // ========================================
  // 1. PostgreSQL Connection (Fully Implemented)
  // ========================================
  print('1. PostgreSQL Connection:');
  try {
    final pgConfig = DatabaseConfig.postgresql(
      host: 'localhost',
      port: 5432,
      database: 'mydb',
      username: 'postgres',
      password: 'password',
      useSSL: false,
    );

    final pgConnection = await DatabaseFactory.createConnection(pgConfig);
    print('   ✓ PostgreSQL connected: ${pgConnection.databaseType}');
    print('   ✓ Connection open: ${pgConnection.isOpen}');

    // Example query
    final results = await pgConnection.query(
      'SELECT version()',
      parameters: {},
    );
    print('   ✓ Query executed successfully');

    await pgConnection.close();
    print('   ✓ Connection closed\n');
  } catch (e) {
    print('   ✗ PostgreSQL error: $e\n');
  }

  // ========================================
  // 2. SQLite3 Connection (Fully Implemented)
  // ========================================
  print('2. SQLite3 Connection:');
  try {
    final sqliteConfig = DatabaseConfig.sqlite(
      filePath: ':memory:', // In-memory database for testing
    );

    final sqliteConnection = await DatabaseFactory.createConnection(
      sqliteConfig,
    );
    print('   ✓ SQLite3 connected: ${sqliteConnection.databaseType}');
    print('   ✓ Connection open: ${sqliteConnection.isOpen}');

    // Create a test table
    await sqliteConnection.execute(
      'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, email TEXT)',
    );
    print('   ✓ Table created');

    // Insert data
    await sqliteConnection.execute(
      'INSERT INTO users (name, email) VALUES (@name, @email)',
      parameters: {'name': 'John Doe', 'email': 'john@example.com'},
    );
    print('   ✓ Data inserted');

    // Query data
    final users = await sqliteConnection.query(
      'SELECT * FROM users WHERE email = @email',
      parameters: {'email': 'john@example.com'},
    );
    print('   ✓ Query results: ${users.length} rows');
    if (users.isNotEmpty) {
      print('   ✓ User: ${users.first}');
    }

    // Transaction example
    final transaction = await sqliteConnection.beginTransaction();
    await transaction.execute(
      'INSERT INTO users (name, email) VALUES (@name, @email)',
      parameters: {'name': 'Jane Doe', 'email': 'jane@example.com'},
    );
    await transaction.commit();
    print('   ✓ Transaction committed');

    await sqliteConnection.close();
    print('   ✓ Connection closed\n');
  } catch (e) {
    print('   ✗ SQLite3 error: $e\n');
  }

  // ========================================
  // 3. MySQL Connection (Structure Ready)
  // ========================================
  print('3. MySQL Connection:');
  print('   ℹ MySQL implementation is ready but requires mysql1 package');
  print('   ℹ To enable MySQL support:');
  print('     1. Add "mysql1: ^0.20.0" to pubspec.yaml');
  print('     2. Uncomment implementation code in mysql_connection.dart');
  print('   ℹ Usage will be:');
  print('''
     final mysqlConfig = DatabaseConfig.mysql(
       host: 'localhost',
       port: 3306,
       database: 'mydb',
       username: 'root',
       password: 'password',
     );
     final mysqlConnection = await DatabaseFactory.createConnection(mysqlConfig);
  ''');

  // ========================================
  // Connection Pool Example (SQLite)
  // ========================================
  print('\n4. Connection Pool Example (SQLite):');
  try {
    final poolConfig = DatabaseConfig.sqlite(filePath: ':memory:');
    final pool = await DatabaseFactory.createPool(
      poolConfig,
      maxConnections: 5,
    );

    print('   ✓ Pool created with max 5 connections');
    print('   ✓ Pool stats: ${pool.stats}');

    // Get connection from pool
    final conn1 = await pool.getConnection();
    print('   ✓ Connection 1 acquired');
    print('   ✓ Pool stats: ${pool.stats}');

    final conn2 = await pool.getConnection();
    print('   ✓ Connection 2 acquired');
    print('   ✓ Pool stats: ${pool.stats}');

    // Release connections
    await pool.releaseConnection(conn1);
    print('   ✓ Connection 1 released');
    print('   ✓ Pool stats: ${pool.stats}');

    await pool.releaseConnection(conn2);
    print('   ✓ Connection 2 released');
    print('   ✓ Pool stats: ${pool.stats}');

    await pool.close();
    print('   ✓ Pool closed\n');
  } catch (e) {
    print('   ✗ Pool error: $e\n');
  }

  print('=== Example Complete ===');
}
