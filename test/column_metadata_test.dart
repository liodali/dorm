import 'package:test/test.dart';
import 'package:dormql/src/column_metadata.dart';

void main() {
  group('ColumnMetadata', () {
    test('creates column metadata with all properties', () {
      final column = ColumnMetadata(
        fieldName: 'firstName',
        columnName: 'first_name',
        dartType: 'String',
        sqlType: 'TEXT',
        isPrimaryKey: false,
        isNullable: true,
        tableName: 'users',
      );

      expect(column.fieldName, 'firstName');
      expect(column.columnName, 'first_name');
      expect(column.dartType, 'String');
      expect(column.sqlType, 'TEXT');
      expect(column.isPrimaryKey, false);
      expect(column.isNullable, true);
      expect(column.tableName, 'users');
    });

    test('creates primary key column metadata', () {
      final column = ColumnMetadata(
        fieldName: 'id',
        columnName: 'id',
        dartType: 'int',
        sqlType: 'INTEGER',
        isPrimaryKey: true,
        isNullable: false,
        tableName: 'users',
      );

      expect(column.isPrimaryKey, true);
      expect(column.isNullable, false);
    });

    test('qualifiedName returns table.column format', () {
      final column = ColumnMetadata(
        fieldName: 'email',
        columnName: 'email',
        dartType: 'String',
        sqlType: 'VARCHAR',
        isPrimaryKey: false,
        isNullable: false,
        tableName: 'users',
      );

      expect(column.qualifiedName, 'users.email');
    });

    test('toSql returns column name', () {
      final column = ColumnMetadata(
        fieldName: 'createdAt',
        columnName: 'created_at',
        dartType: 'DateTime',
        sqlType: 'TIMESTAMP',
        isPrimaryKey: false,
        isNullable: false,
        tableName: 'posts',
      );

      expect(column.toSql(), 'created_at');
    });

    test('toString returns column name', () {
      final column = ColumnMetadata(
        fieldName: 'status',
        columnName: 'status',
        dartType: 'String',
        sqlType: 'VARCHAR',
        isPrimaryKey: false,
        isNullable: true,
        tableName: 'orders',
      );

      expect(column.toString(), 'status');
    });

    group('Equality', () {
      test('two identical columns are equal', () {
        final column1 = ColumnMetadata(
          fieldName: 'name',
          columnName: 'name',
          dartType: 'String',
          sqlType: 'TEXT',
          isPrimaryKey: false,
          isNullable: true,
          tableName: 'users',
        );

        final column2 = ColumnMetadata(
          fieldName: 'name',
          columnName: 'name',
          dartType: 'String',
          sqlType: 'TEXT',
          isPrimaryKey: false,
          isNullable: true,
          tableName: 'users',
        );

        expect(column1, equals(column2));
        expect(column1.hashCode, equals(column2.hashCode));
      });

      test('columns with different field names are not equal', () {
        final column1 = ColumnMetadata(
          fieldName: 'firstName',
          columnName: 'first_name',
          dartType: 'String',
          sqlType: 'TEXT',
          isPrimaryKey: false,
          isNullable: true,
          tableName: 'users',
        );

        final column2 = ColumnMetadata(
          fieldName: 'lastName',
          columnName: 'first_name',
          dartType: 'String',
          sqlType: 'TEXT',
          isPrimaryKey: false,
          isNullable: true,
          tableName: 'users',
        );

        expect(column1, isNot(equals(column2)));
      });

      test('columns with different table names are not equal', () {
        final column1 = ColumnMetadata(
          fieldName: 'id',
          columnName: 'id',
          dartType: 'int',
          sqlType: 'INTEGER',
          isPrimaryKey: true,
          isNullable: false,
          tableName: 'users',
        );

        final column2 = ColumnMetadata(
          fieldName: 'id',
          columnName: 'id',
          dartType: 'int',
          sqlType: 'INTEGER',
          isPrimaryKey: true,
          isNullable: false,
          tableName: 'posts',
        );

        expect(column1, isNot(equals(column2)));
      });

      test('same instance is equal to itself', () {
        final column = ColumnMetadata(
          fieldName: 'id',
          columnName: 'id',
          dartType: 'int',
          sqlType: 'INTEGER',
          isPrimaryKey: true,
          isNullable: false,
          tableName: 'users',
        );

        expect(column, equals(column));
      });
    });

    group('Nullable Types', () {
      test('handles nullable Dart types', () {
        final column = ColumnMetadata(
          fieldName: 'middleName',
          columnName: 'middle_name',
          dartType: 'String?',
          sqlType: 'TEXT',
          isPrimaryKey: false,
          isNullable: true,
          tableName: 'users',
        );

        expect(column.dartType, 'String?');
        expect(column.isNullable, true);
      });

      test('handles non-nullable Dart types', () {
        final column = ColumnMetadata(
          fieldName: 'age',
          columnName: 'age',
          dartType: 'int',
          sqlType: 'INTEGER',
          isPrimaryKey: false,
          isNullable: false,
          tableName: 'users',
        );

        expect(column.dartType, 'int');
        expect(column.isNullable, false);
      });
    });
  });
}
