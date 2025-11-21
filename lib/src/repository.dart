import 'package:dorm/src/query_builder.dart';
import 'package:dorm/src/raw_query.dart';
import 'package:dorm/src/database/database_connection.dart';
import 'package:dorm/src/stored_procedure.dart';

abstract class Repository<T> {
  final String tableName;
  late DatabaseConnection connection;

  Repository(this.tableName);

  /// Convert database row to entity
  T fromRow(Map<String, dynamic> row);

  /// Convert entity to database row
  Map<String, dynamic> toRow(T entity);

  /// Initialize repository with connection
  void setConnection(DatabaseConnection conn) {
    connection = conn;
  }

  /// Save entity (INSERT or UPDATE)
  Future<T> save(T entity) async {
    final row = toRow(entity);
    final columns = row.keys.join(', ');
    final placeholders = row.keys.map((k) => '@$k').join(', ');

    final sql =
        'INSERT INTO $tableName ($columns) VALUES ($placeholders) RETURNING *';

    final result = await connection.query(
      sql,
      parameters: row,
    );
    if (result.isEmpty) throw Exception('Save failed');

    return fromRow(result.first);
  }

  /// Find by primary key
  Future<T?> findById(dynamic id) async {
    final sql = 'SELECT * FROM $tableName WHERE id = @id';
    final results = await executeQuery(sql, {'id': id}, []);
    return results.isNotEmpty ? results.first : null;
  }

  /// Get all records
  Future<List<T>> getAll() {
    return query().toList();
  }

  /// Delete entity by ID
  Future<void> delete(dynamic id) async {
    final sql = 'DELETE FROM $tableName WHERE id = @id';
    await connection.execute(sql, parameters: {'id': id});
  }

  /// Delete entity
  Future<void> deleteEntity(T entity) async {
    final row = toRow(entity);
    final id = row['id'];
    await delete(id);
  }

  /// Create query builder
  QueryBuilder<T> query() {
    return QueryBuilder(this);
  }

  /// Execute raw SQL query
  RawQuery executeRawQuery(String sql, [Map<String, dynamic>? parameters]) {
    return RawQuery(connection, sql, parameters ?? {});
  }

  /// Execute stored procedure
  StoredProcedure executeProcedure(String name, {List<dynamic>? parameters}) {
    final proc = StoredProcedure(name: name, parameters: parameters ?? []);
    proc.setConnection(connection);
    return proc;
  }

  /// Execute query (internal)
  Future<List<T>> executeQuery(
    String sql,
    Map<String, dynamic> parameters,
    List<String> includes,
  ) async {
    final result = await connection.query(
      sql,
      parameters: parameters,
    );

    var entities = result.map((r) => fromRow(r)).toList();

    // Load eager relationships
    if (includes.isNotEmpty) {
      for (var entity in entities) {
        await loadRelationships(entity, includes);
      }
    }

    return entities;
  }

  /// Load relationships for an entity (to be implemented by generated code)
  Future<void> loadRelationships(T entity, List<String> includes) async {}

  /// Execute count query (internal)
  Future<int> executeCount(String sql, Map<String, dynamic> parameters) async {
    final result = await connection.query(
      sql,
      parameters: parameters,
    );

    if (result.isEmpty) return 0;
    return (result.first['count'] as int?) ?? 0;
  }
}
