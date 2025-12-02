import 'package:dartorm/src/repository.dart';

/// EntityFramework-style LINQ query builder
class QueryBuilder<T> {
  final Repository<T> repository;
  final List<String> _selects = [];
  final List<String> _wheres = [];
  final Map<String, dynamic> _params = {};
  final List<String> _joins = [];
  final List<String> _orderBys = [];
  final List<String> _includes = [];
  int? _skip;
  int? _take;
  bool _distinct = false;

  QueryBuilder(this.repository);

  /// SELECT specific columns
  QueryBuilder<T> select(Function(SelectBuilder) builder) {
    final sb = SelectBuilder();
    builder(sb);
    _selects.addAll(sb._columns);
    return this;
  }

  /// WHERE clause with condition
  QueryBuilder<T> where(String condition, [Map<String, dynamic>? parameters]) {
    _wheres.add('($condition)');
    if (parameters != null) {
      _params.addAll(parameters);
    }
    return this;
  }

  /// WHERE with lambda-like expression
  QueryBuilder<T> whereSimple(String column, dynamic value) {
    _wheres.add('${_formatColumn(column)} = @${column}_${_params.length}');
    _params['${column}_${_params.length}'] = value;
    return this;
  }

  /// WHERE IN clause
  QueryBuilder<T> whereIn(String column, List<dynamic> values) {
    final placeholders = List.generate(
      values.length,
      (i) => '@${column}_$i',
    ).join(',');
    _wheres.add('${_formatColumn(column)} IN ($placeholders)');
    for (int i = 0; i < values.length; i++) {
      _params['${column}_$i'] = values[i];
    }
    return this;
  }

  /// WHERE NOT IN clause
  QueryBuilder<T> whereNotIn(String column, List<dynamic> values) {
    final placeholders = List.generate(
      values.length,
      (i) => '@${column}_$i',
    ).join(',');
    _wheres.add('${_formatColumn(column)} NOT IN ($placeholders)');
    for (int i = 0; i < values.length; i++) {
      _params['${column}_$i'] = values[i];
    }
    return this;
  }

  /// BETWEEN clause
  QueryBuilder<T> whereBetween(String column, dynamic from, dynamic to) {
    _wheres.add(
      '${_formatColumn(column)} BETWEEN @${column}_from AND @${column}_to',
    );
    _params['${column}_from'] = from;
    _params['${column}_to'] = to;
    return this;
  }

  /// LIKE clause
  QueryBuilder<T> whereLike(String column, String pattern) {
    _wheres.add('${_formatColumn(column)} LIKE @${column}_pattern');
    _params['${column}_pattern'] = pattern;
    return this;
  }

  /// ILIKE clause (PostgreSQL case-insensitive)
  QueryBuilder<T> whereILike(String column, String pattern) {
    _wheres.add('${_formatColumn(column)} ILIKE @${column}_pattern');
    _params['${column}_pattern'] = pattern;
    return this;
  }

  /// IS NULL clause
  QueryBuilder<T> whereNull(String column) {
    _wheres.add('${_formatColumn(column)} IS NULL');
    return this;
  }

  /// IS NOT NULL clause
  QueryBuilder<T> whereNotNull(String column) {
    _wheres.add('${_formatColumn(column)} IS NOT NULL');
    return this;
  }

  /// INNER JOIN
  QueryBuilder<T> innerJoin(String table, String condition) {
    _joins.add('INNER JOIN $table ON $condition');
    return this;
  }

  /// LEFT JOIN
  QueryBuilder<T> leftJoin(String table, String condition) {
    _joins.add('LEFT JOIN $table ON $condition');
    return this;
  }

  /// RIGHT JOIN
  QueryBuilder<T> rightJoin(String table, String condition) {
    _joins.add('RIGHT JOIN $table ON $condition');
    return this;
  }

  /// INNER JOIN with related entity (Include pattern)
  QueryBuilder<T> include(String relationshipName) {
    _includes.add(relationshipName);
    return this;
  }

  /// ORDER BY ascending
  QueryBuilder<T> orderBy(String column) {
    _orderBys.add('${_formatColumn(column)} ASC');
    return this;
  }

  /// ORDER BY descending
  QueryBuilder<T> orderByDescending(String column) {
    _orderBys.add('${_formatColumn(column)} DESC');
    return this;
  }

  /// DISTINCT
  QueryBuilder<T> distinct() {
    _distinct = true;
    return this;
  }

  /// SKIP (OFFSET)
  QueryBuilder<T> skip(int count) {
    _skip = count;
    return this;
  }

  /// TAKE (LIMIT)
  QueryBuilder<T> take(int count) {
    _take = count;
    return this;
  }

  /// Execute and get all results
  Future<List<T>> toList() async {
    final sql = _buildSql();
    return repository.executeQuery(sql, _params, _includes);
  }

  /// Execute and get first result
  Future<T?> firstOrDefault() async {
    take(1);
    final results = await toList();
    return results.isNotEmpty ? results.first : null;
  }

  /// Execute and get first result (throws if not found)
  Future<T> first() async {
    final result = await firstOrDefault();
    if (result == null) {
      throw Exception('No matching record found');
    }
    return result;
  }

  /// Count matching records
  Future<int> countSql() async {
    final sql = _buildCountSql();
    return repository.executeCount(sql, _params);
  }

  /// Check if any records match
  Future<bool> any() async {
    final count = await countSql();
    return count > 0;
  }

  /// Get maximum value of a column
  Future<num?> max(String column) async {
    final sql = _buildAggregateSql('MAX', column);
    final result = await repository.connection.query(sql, parameters: _params);
    if (result.isEmpty) return null;
    final value = result.first['max_value'];
    return value != null ? (value as num) : null;
  }

  /// Get minimum value of a column
  Future<num?> min(String column) async {
    final sql = _buildAggregateSql('MIN', column);
    final result = await repository.connection.query(sql, parameters: _params);
    if (result.isEmpty) return null;
    final value = result.first['min_value'];
    return value != null ? (value as num) : null;
  }

  /// Get sum of a column
  Future<num?> sum(String column) async {
    final sql = _buildAggregateSql('SUM', column);
    final result = await repository.connection.query(sql, parameters: _params);
    if (result.isEmpty) return null;
    final value = result.first['sum_value'];
    return value != null ? (value as num) : null;
  }

  /// Get average of a column
  Future<num?> avg(String column) async {
    final sql = _buildAggregateSql('AVG', column);
    final result = await repository.connection.query(sql, parameters: _params);
    if (result.isEmpty) return null;
    final value = result.first['avg_value'];
    return value != null ? (value as num) : null;
  }

  /// Get SQL string (for debugging)
  String toSql() {
    return _buildSql();
  }

  String _buildSql() {
    final sb = StringBuffer();

    sb.write('SELECT ${_distinct ? 'DISTINCT ' : ''}');
    sb.write(
      _selects.isEmpty ? '${repository.tableName}.*' : _selects.join(', '),
    );
    sb.write(' FROM ${repository.tableName}');

    if (_joins.isNotEmpty) {
      sb.write(' ${_joins.join(' ')}');
    }

    if (_wheres.isNotEmpty) {
      sb.write(' WHERE ${_wheres.join(' AND ')}');
    }

    if (_orderBys.isNotEmpty) {
      sb.write(' ORDER BY ${_orderBys.join(', ')}');
    }

    if (_skip != null) {
      sb.write(' OFFSET $_skip');
    }

    if (_take != null) {
      sb.write(' LIMIT $_take');
    }

    return sb.toString();
  }

  String _buildCountSql() {
    final sb = StringBuffer();
    sb.write('SELECT COUNT(*) as count FROM ${repository.tableName}');

    if (_joins.isNotEmpty) {
      sb.write(' ${_joins.join(' ')}');
    }

    if (_wheres.isNotEmpty) {
      sb.write(' WHERE ${_wheres.join(' AND ')}');
    }

    return sb.toString();
  }

  String _buildAggregateSql(String function, String column) {
    final sb = StringBuffer();
    final formattedColumn = _formatColumn(column);
    final alias = '${function.toLowerCase()}_value';

    sb.write(
      'SELECT $function($formattedColumn) as $alias FROM ${repository.tableName}',
    );

    if (_joins.isNotEmpty) {
      sb.write(' ${_joins.join(' ')}');
    }

    if (_wheres.isNotEmpty) {
      sb.write(' WHERE ${_wheres.join(' AND ')}');
    }

    return sb.toString();
  }

  String _formatColumn(String col) {
    return col.contains('.') ? col : '${repository.tableName}.$col';
  }
}

class SelectBuilder {
  final List<String> _columns = [];

  void column(String name) => _columns.add(name);
  void columns(List<String> names) => _columns.addAll(names);
}
