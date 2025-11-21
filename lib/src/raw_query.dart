import 'database/database_connection.dart';

/// Execute raw SQL queries with parameterization
class RawQuery {
  final String sql;
  final Map<String, dynamic> parameters;
  final DatabaseConnection _connection;

  RawQuery(this._connection, this.sql, [this.parameters = const {}]);

  /// Execute query and return rows as maps
  Future<List<Map<String, dynamic>>> execute() async {
    return _executeParameterized();
  }

  /// Execute query returning first result
  Future<Map<String, dynamic>?> executeFirstOrDefault() async {
    final results = await execute();
    return results.isNotEmpty ? results.first : null;
  }

  /// Execute scalar query (single value)
  Future<dynamic> executeScalar() async {
    final result = await executeFirstOrDefault();
    if (result == null) return null;
    return result.values.first;
  }

  /// Execute non-query (INSERT, UPDATE, DELETE)
  Future<int> executeNonQuery() async {
    final result = await _connection.execute(
      sql,
      parameters: parameters,
    );
    return result;
  }

  /// Get generated SQL with parameters
  String toSql() {
    var result = sql;
    parameters.forEach((key, value) {
      final placeholder = '@$key';
      result = result.replaceAll(placeholder, _formatValue(value));
    });
    return result;
  }

  Future<List<Map<String, dynamic>>> _executeParameterized() async {
    final result = await _connection.query(
      sql,
      parameters: parameters,
    );
    return result;
  }

  String _formatValue(dynamic value) {
    if (value == null) return 'NULL';
    if (value is String) return "'${value.replaceAll("'", "''")}'";
    if (value is bool) return value ? 'true' : 'false';
    if (value is DateTime) return "'${value.toIso8601String()}'";
    return value.toString();
  }
}
