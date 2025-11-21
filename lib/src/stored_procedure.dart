import 'database/database_connection.dart';

/// Execute database stored procedures
class StoredProcedure {
  final String name;
  final String schema;
  final List<dynamic> parameters;
  DatabaseConnection? _connection;

  StoredProcedure({
    required this.name,
    this.schema = 'public',
    this.parameters = const [],
    DatabaseConnection? connection,
  }) : _connection = connection;

  /// Set connection
  void setConnection(DatabaseConnection connection) {
    _connection = connection;
  }

  /// Execute procedure and return results
  Future<List<Map<String, dynamic>>> execute() async {
    if (_connection == null) {
      throw StateError('Connection not set. Call setConnection() first.');
    }

    final fullName = '$schema.$name';
    final placeholders = List.generate(
      parameters.length,
      (i) => '@param$i',
    ).join(',');

    final sql = 'SELECT * FROM $fullName($placeholders)';
    final params = <String, dynamic>{};
    for (var i = 0; i < parameters.length; i++) {
      params['param$i'] = parameters[i];
    }

    final result = await _connection!.query(
      sql,
      parameters: params,
    );

    return result;
  }

  /// Execute procedure and get scalar result
  Future<dynamic> executeScalar() async {
    final results = await execute();
    if (results.isEmpty) return null;
    return results.first.values.first;
  }

  /// Execute procedure for non-query operations
  Future<void> executeNonQuery() async {
    if (_connection == null) {
      throw StateError('Connection not set. Call setConnection() first.');
    }

    final fullName = '$schema.$name';
    final placeholders = List.generate(
      parameters.length,
      (i) => '@param$i',
    ).join(',');

    final sql = 'CALL $fullName($placeholders)';
    final params = <String, dynamic>{};
    for (var i = 0; i < parameters.length; i++) {
      params['param$i'] = parameters[i];
    }

    await _connection!.execute(sql, parameters: params);
  }
}

/// Builder for creating stored procedures
class StoredProcedureBuilder {
  final DatabaseConnection _connection;
  final String _name;
  String _schema = 'public';
  final List<dynamic> _parameters = [];

  StoredProcedureBuilder(this._connection, this._name);

  StoredProcedureBuilder withSchema(String schema) {
    _schema = schema;
    return this;
  }

  StoredProcedureBuilder addParameter(dynamic value) {
    _parameters.add(value);
    return this;
  }

  StoredProcedure build() {
    return StoredProcedure(
      name: _name,
      schema: _schema,
      parameters: _parameters,
      connection: _connection,
    );
  }
}
