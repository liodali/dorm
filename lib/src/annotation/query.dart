/// Stored procedure annotation for calling database stored procedures
class StoredProcedureAnnotation {
  final String name;
  final String? schema;
  final String? description;

  const StoredProcedureAnnotation({
    required this.name,
    this.schema = 'public',
    this.description,
  });
}

/// Raw query annotation for custom SQL queries
class Query {
  final String sql;
  final QueryType type;
  final String? description;

  const Query({
    required this.sql,
    this.type = QueryType.select,
    this.description,
  });
}

/// Query types for the Query annotation
enum QueryType { select, insert, update, delete }
