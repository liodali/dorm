import 'package:test/test.dart';
import 'package:dormql/src/schema.dart';
import 'package:dormql/src/database/database_connection.dart';

void main() {
  group('ColumnSchema', () {
    test('creates column with required properties', () {
      const column = ColumnSchema(
        name: 'id',
        type: 'INTEGER',
      );

      expect(column.name, 'id');
      expect(column.type, 'INTEGER');
      expect(column.nullable, true);
      expect(column.primaryKey, false);
      expect(column.unique, false);
      expect(column.defaultValue, isNull);
      expect(column.autoIncrement, false);
    });

    test('creates primary key column', () {
      const column = ColumnSchema(
        name: 'id',
        type: 'INTEGER',
        primaryKey: true,
        nullable: false,
        autoIncrement: true,
      );

      expect(column.primaryKey, true);
      expect(column.nullable, false);
      expect(column.autoIncrement, true);
    });

    test('creates column with default value', () {
      const column = ColumnSchema(
        name: 'status',
        type: 'VARCHAR',
        defaultValue: "'active'",
      );

      expect(column.defaultValue, "'active'");
    });

    test('creates unique column', () {
      const column = ColumnSchema(
        name: 'email',
        type: 'VARCHAR',
        unique: true,
        nullable: false,
      );

      expect(column.unique, true);
      expect(column.nullable, false);
    });

    group('toSql', () {
      test('generates SQL for simple column', () {
        const column = ColumnSchema(
          name: 'name',
          type: 'TEXT',
        );

        final sql = column.toSql(DatabaseType.postgresql);
        expect(sql, 'name TEXT');
      });

      test('generates SQL for NOT NULL column', () {
        const column = ColumnSchema(
          name: 'email',
          type: 'VARCHAR',
          nullable: false,
        );

        final sql = column.toSql(DatabaseType.postgresql);
        expect(sql, 'email VARCHAR NOT NULL');
      });

      test('generates SQL for UNIQUE column', () {
        const column = ColumnSchema(
          name: 'username',
          type: 'VARCHAR',
          unique: true,
          nullable: false,
        );

        final sql = column.toSql(DatabaseType.postgresql);
        expect(sql, 'username VARCHAR NOT NULL UNIQUE');
      });

      test('generates SQL for column with default value', () {
        const column = ColumnSchema(
          name: 'status',
          type: 'VARCHAR',
          defaultValue: "'active'",
        );

        final sql = column.toSql(DatabaseType.postgresql);
        expect(sql, "status VARCHAR DEFAULT 'active'");
      });

      test('generates SQL for PRIMARY KEY column in PostgreSQL', () {
        const column = ColumnSchema(
          name: 'id',
          type: 'INTEGER',
          primaryKey: true,
          autoIncrement: true,
        );

        final sql = column.toSql(DatabaseType.postgresql);
        expect(sql, 'id SERIAL PRIMARY KEY');
      });

      test('generates SQL for PRIMARY KEY column in MySQL', () {
        const column = ColumnSchema(
          name: 'id',
          type: 'INTEGER',
          primaryKey: true,
          autoIncrement: true,
        );

        final sql = column.toSql(DatabaseType.mysql);
        expect(sql, 'id INTEGER AUTO_INCREMENT PRIMARY KEY');
      });

      test('generates SQL for PRIMARY KEY column in SQLite', () {
        const column = ColumnSchema(
          name: 'id',
          type: 'INTEGER',
          primaryKey: true,
          autoIncrement: true,
        );

        final sql = column.toSql(DatabaseType.sqlite);
        expect(sql, 'id INTEGER PRIMARY KEY');
      });

      test('generates SQL for BIGINT autoincrement in PostgreSQL', () {
        const column = ColumnSchema(
          name: 'id',
          type: 'BIGINT',
          primaryKey: true,
          autoIncrement: true,
        );

        final sql = column.toSql(DatabaseType.postgresql);
        expect(sql, 'id BIGSERIAL PRIMARY KEY');
      });
    });
  });

  group('ForeignKey', () {
    test('creates foreign key with required properties', () {
      const fk = ForeignKey(
        column: 'user_id',
        referencedTable: 'users',
        referencedColumn: 'id',
      );

      expect(fk.column, 'user_id');
      expect(fk.referencedTable, 'users');
      expect(fk.referencedColumn, 'id');
      expect(fk.onDelete, isNull);
      expect(fk.onUpdate, isNull);
      expect(fk.name, isNull);
    });

    test('creates foreign key with cascade actions', () {
      const fk = ForeignKey(
        column: 'user_id',
        referencedTable: 'users',
        referencedColumn: 'id',
        onDelete: ForeignKeyAction.cascade,
        onUpdate: ForeignKeyAction.cascade,
      );

      expect(fk.onDelete, ForeignKeyAction.cascade);
      expect(fk.onUpdate, ForeignKeyAction.cascade);
    });

    test('creates foreign key with custom name', () {
      const fk = ForeignKey(
        column: 'user_id',
        referencedTable: 'users',
        referencedColumn: 'id',
        name: 'fk_posts_user',
      );

      expect(fk.name, 'fk_posts_user');
    });

    group('toSql', () {
      test('generates SQL for simple foreign key', () {
        const fk = ForeignKey(
          column: 'user_id',
          referencedTable: 'users',
          referencedColumn: 'id',
        );

        final sql = fk.toSql(DatabaseType.postgresql);
        expect(sql, 'FOREIGN KEY (user_id) REFERENCES users (id)');
      });

      test('generates SQL for foreign key with name', () {
        const fk = ForeignKey(
          column: 'user_id',
          referencedTable: 'users',
          referencedColumn: 'id',
          name: 'fk_posts_user',
        );

        final sql = fk.toSql(DatabaseType.postgresql);
        expect(
          sql,
          'CONSTRAINT fk_posts_user FOREIGN KEY (user_id) REFERENCES users (id)',
        );
      });

      test('generates SQL for foreign key with CASCADE', () {
        const fk = ForeignKey(
          column: 'user_id',
          referencedTable: 'users',
          referencedColumn: 'id',
          onDelete: ForeignKeyAction.cascade,
          onUpdate: ForeignKeyAction.cascade,
        );

        final sql = fk.toSql(DatabaseType.postgresql);
        expect(
          sql,
          'FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE ON UPDATE CASCADE',
        );
      });

      test('generates SQL for foreign key with SET NULL', () {
        const fk = ForeignKey(
          column: 'user_id',
          referencedTable: 'users',
          referencedColumn: 'id',
          onDelete: ForeignKeyAction.setNull,
        );

        final sql = fk.toSql(DatabaseType.postgresql);
        expect(
          sql,
          'FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL',
        );
      });
    });
  });

  group('ForeignKeyAction', () {
    test('toSql returns correct SQL for each action', () {
      expect(ForeignKeyAction.cascade.toSql(), 'CASCADE');
      expect(ForeignKeyAction.restrict.toSql(), 'RESTRICT');
      expect(ForeignKeyAction.setNull.toSql(), 'SET NULL');
      expect(ForeignKeyAction.setDefault.toSql(), 'SET DEFAULT');
      expect(ForeignKeyAction.noAction.toSql(), 'NO ACTION');
    });
  });

  group('IndexSchema', () {
    test('creates index with required properties', () {
      const index = IndexSchema(
        name: 'idx_users_email',
        columns: ['email'],
      );

      expect(index.name, 'idx_users_email');
      expect(index.columns, ['email']);
      expect(index.unique, false);
    });

    test('creates unique index', () {
      const index = IndexSchema(
        name: 'idx_users_email',
        columns: ['email'],
        unique: true,
      );

      expect(index.unique, true);
    });

    test('creates composite index', () {
      const index = IndexSchema(
        name: 'idx_users_name',
        columns: ['first_name', 'last_name'],
      );

      expect(index.columns, ['first_name', 'last_name']);
    });
  });

  group('UniqueConstraint', () {
    test('creates unique constraint', () {
      const constraint = UniqueConstraint(columns: ['email']);

      expect(constraint.columns, ['email']);
      expect(constraint.name, isNull);
    });

    test('creates unique constraint with name', () {
      const constraint = UniqueConstraint(
        columns: ['email'],
        name: 'uq_users_email',
      );

      expect(constraint.name, 'uq_users_email');
    });

    test('creates composite unique constraint', () {
      const constraint = UniqueConstraint(
        columns: ['first_name', 'last_name'],
      );

      expect(constraint.columns, ['first_name', 'last_name']);
    });
  });

  group('CheckConstraint', () {
    test('creates check constraint', () {
      const constraint = CheckConstraint(expression: 'age >= 18');

      expect(constraint.expression, 'age >= 18');
      expect(constraint.name, isNull);
    });

    test('creates check constraint with name', () {
      const constraint = CheckConstraint(
        expression: 'age >= 18',
        name: 'chk_users_age',
      );

      expect(constraint.name, 'chk_users_age');
    });
  });

  group('DatabaseSchema', () {
    test('creates schema with required properties', () {
      const schema = DatabaseSchema(
        tableName: 'users',
        columns: [
          ColumnSchema(name: 'id', type: 'INTEGER', primaryKey: true),
          ColumnSchema(name: 'name', type: 'TEXT'),
        ],
      );

      expect(schema.tableName, 'users');
      expect(schema.columns.length, 2);
      expect(schema.foreignKeys, isNull);
      expect(schema.indexes, isNull);
      expect(schema.primaryKeyColumns, isNull);
      expect(schema.uniqueConstraints, isNull);
      expect(schema.checkConstraints, isNull);
    });

    test('creates schema with all properties', () {
      const schema = DatabaseSchema(
        tableName: 'posts',
        columns: [
          ColumnSchema(name: 'id', type: 'INTEGER'),
          ColumnSchema(name: 'title', type: 'TEXT'),
          ColumnSchema(name: 'user_id', type: 'INTEGER'),
        ],
        foreignKeys: [
          ForeignKey(
            column: 'user_id',
            referencedTable: 'users',
            referencedColumn: 'id',
          ),
        ],
        indexes: [
          IndexSchema(name: 'idx_posts_user_id', columns: ['user_id']),
        ],
        primaryKeyColumns: ['id'],
        uniqueConstraints: [
          UniqueConstraint(columns: ['title']),
        ],
        checkConstraints: [
          CheckConstraint(expression: 'LENGTH(title) >= 5'),
        ],
      );

      expect(schema.foreignKeys!.length, 1);
      expect(schema.indexes!.length, 1);
      expect(schema.primaryKeyColumns, ['id']);
      expect(schema.uniqueConstraints!.length, 1);
      expect(schema.checkConstraints!.length, 1);
    });

    group('toCreateTableSql', () {
      test('generates CREATE TABLE SQL for simple schema', () {
        const schema = DatabaseSchema(
          tableName: 'users',
          columns: [
            ColumnSchema(name: 'id', type: 'INTEGER', primaryKey: true),
            ColumnSchema(name: 'name', type: 'TEXT', nullable: false),
          ],
        );

        final sql = schema.toCreateTableSql(DatabaseType.postgresql);

        expect(sql, contains('CREATE TABLE IF NOT EXISTS users'));
        expect(sql, contains('id INTEGER PRIMARY KEY'));
        expect(sql, contains('name TEXT NOT NULL'));
      });

      test('generates CREATE TABLE SQL with composite primary key', () {
        const schema = DatabaseSchema(
          tableName: 'user_roles',
          columns: [
            ColumnSchema(name: 'user_id', type: 'INTEGER'),
            ColumnSchema(name: 'role_id', type: 'INTEGER'),
          ],
          primaryKeyColumns: ['user_id', 'role_id'],
        );

        final sql = schema.toCreateTableSql(DatabaseType.postgresql);

        expect(sql, contains('PRIMARY KEY (user_id, role_id)'));
      });

      test('generates CREATE TABLE SQL with foreign keys', () {
        const schema = DatabaseSchema(
          tableName: 'posts',
          columns: [
            ColumnSchema(name: 'id', type: 'INTEGER', primaryKey: true),
            ColumnSchema(name: 'user_id', type: 'INTEGER'),
          ],
          foreignKeys: [
            ForeignKey(
              column: 'user_id',
              referencedTable: 'users',
              referencedColumn: 'id',
              onDelete: ForeignKeyAction.cascade,
            ),
          ],
        );

        final sql = schema.toCreateTableSql(DatabaseType.postgresql);

        expect(sql, contains('FOREIGN KEY (user_id) REFERENCES users (id)'));
        expect(sql, contains('ON DELETE CASCADE'));
      });

      test('generates CREATE TABLE SQL with unique constraints', () {
        const schema = DatabaseSchema(
          tableName: 'users',
          columns: [
            ColumnSchema(name: 'id', type: 'INTEGER', primaryKey: true),
            ColumnSchema(name: 'email', type: 'VARCHAR'),
          ],
          uniqueConstraints: [
            UniqueConstraint(columns: ['email'], name: 'uq_users_email'),
          ],
        );

        final sql = schema.toCreateTableSql(DatabaseType.postgresql);

        expect(sql, contains('CONSTRAINT uq_users_email UNIQUE (email)'));
      });

      test('generates CREATE TABLE SQL with check constraints', () {
        const schema = DatabaseSchema(
          tableName: 'users',
          columns: [
            ColumnSchema(name: 'id', type: 'INTEGER', primaryKey: true),
            ColumnSchema(name: 'age', type: 'INTEGER'),
          ],
          checkConstraints: [
            CheckConstraint(expression: 'age >= 18', name: 'chk_users_age'),
          ],
        );

        final sql = schema.toCreateTableSql(DatabaseType.postgresql);

        expect(sql, contains('CONSTRAINT chk_users_age CHECK (age >= 18)'));
      });

      test('generates CREATE TABLE SQL with ENGINE for MySQL', () {
        const schema = DatabaseSchema(
          tableName: 'users',
          columns: [
            ColumnSchema(name: 'id', type: 'INTEGER', primaryKey: true),
          ],
        );

        final sql = schema.toCreateTableSql(DatabaseType.mysql);

        expect(sql, contains('ENGINE=InnoDB'));
      });

      test('does not add ENGINE for PostgreSQL', () {
        const schema = DatabaseSchema(
          tableName: 'users',
          columns: [
            ColumnSchema(name: 'id', type: 'INTEGER', primaryKey: true),
          ],
        );

        final sql = schema.toCreateTableSql(DatabaseType.postgresql);

        expect(sql, isNot(contains('ENGINE')));
      });
    });

    group('toCreateIndexSql', () {
      test('generates CREATE INDEX SQL', () {
        const schema = DatabaseSchema(
          tableName: 'users',
          columns: [
            ColumnSchema(name: 'id', type: 'INTEGER', primaryKey: true),
            ColumnSchema(name: 'email', type: 'VARCHAR'),
          ],
          indexes: [
            IndexSchema(name: 'idx_users_email', columns: ['email']),
          ],
        );

        final sqls = schema.toCreateIndexSql(DatabaseType.postgresql);

        expect(sqls.length, 1);
        expect(
          sqls[0],
          'CREATE INDEX IF NOT EXISTS idx_users_email ON users (email);',
        );
      });

      test('generates CREATE UNIQUE INDEX SQL', () {
        const schema = DatabaseSchema(
          tableName: 'users',
          columns: [
            ColumnSchema(name: 'id', type: 'INTEGER', primaryKey: true),
            ColumnSchema(name: 'email', type: 'VARCHAR'),
          ],
          indexes: [
            IndexSchema(
              name: 'idx_users_email',
              columns: ['email'],
              unique: true,
            ),
          ],
        );

        final sqls = schema.toCreateIndexSql(DatabaseType.postgresql);

        expect(sqls[0], contains('CREATE UNIQUE INDEX'));
      });

      test('generates multiple CREATE INDEX SQL', () {
        const schema = DatabaseSchema(
          tableName: 'users',
          columns: [
            ColumnSchema(name: 'id', type: 'INTEGER', primaryKey: true),
            ColumnSchema(name: 'email', type: 'VARCHAR'),
            ColumnSchema(name: 'name', type: 'TEXT'),
          ],
          indexes: [
            IndexSchema(name: 'idx_users_email', columns: ['email']),
            IndexSchema(name: 'idx_users_name', columns: ['name']),
          ],
        );

        final sqls = schema.toCreateIndexSql(DatabaseType.postgresql);

        expect(sqls.length, 2);
      });

      test('returns empty list when no indexes', () {
        const schema = DatabaseSchema(
          tableName: 'users',
          columns: [
            ColumnSchema(name: 'id', type: 'INTEGER', primaryKey: true),
          ],
        );

        final sqls = schema.toCreateIndexSql(DatabaseType.postgresql);

        expect(sqls, isEmpty);
      });
    });

    group('toDropTableSql', () {
      test('generates DROP TABLE SQL', () {
        const schema = DatabaseSchema(
          tableName: 'users',
          columns: [
            ColumnSchema(name: 'id', type: 'INTEGER', primaryKey: true),
          ],
        );

        final sql = schema.toDropTableSql(DatabaseType.postgresql);

        expect(sql, 'DROP TABLE IF EXISTS users;');
      });
    });

    group('toAllSql', () {
      test('generates all SQL statements', () {
        const schema = DatabaseSchema(
          tableName: 'users',
          columns: [
            ColumnSchema(name: 'id', type: 'INTEGER', primaryKey: true),
            ColumnSchema(name: 'email', type: 'VARCHAR'),
          ],
          indexes: [
            IndexSchema(name: 'idx_users_email', columns: ['email']),
          ],
        );

        final sqls = schema.toAllSql(DatabaseType.postgresql);

        expect(sqls.length, 2);
        expect(sqls[0], contains('CREATE TABLE'));
        expect(sqls[1], contains('CREATE INDEX'));
      });
    });
  });

  group('SQLType', () {
    test('has all expected enum values', () {
      expect(SQLType.values, contains(SQLType.integer));
      expect(SQLType.values, contains(SQLType.bigint));
      expect(SQLType.values, contains(SQLType.text));
      expect(SQLType.values, contains(SQLType.varchar));
      expect(SQLType.values, contains(SQLType.boolean));
      expect(SQLType.values, contains(SQLType.timestamp));
      expect(SQLType.values, contains(SQLType.json));
      expect(SQLType.values, contains(SQLType.jsonb));
      expect(SQLType.values, contains(SQLType.uuid));
    });

    test('fromName returns correct SQLType', () {
      expect(SQLType.fromName('integer'), SQLType.integer);
      expect(SQLType.fromName('text'), SQLType.text);
      expect(SQLType.fromName('boolean'), SQLType.boolean);
      expect(SQLType.fromName('timestamp'), SQLType.timestamp);
    });

    test('fromName returns text for unknown type', () {
      expect(SQLType.fromName('unknown_type'), SQLType.text);
    });

    test('toSql returns correct SQL type string', () {
      expect(SQLType.toSql('integer'), 'INTEGER');
      expect(SQLType.toSql('text'), 'TEXT');
      expect(SQLType.toSql('boolean'), 'BOOLEAN');
      expect(SQLType.toSql('timestamp'), 'TIMESTAMP');
    });

    test('toSqlForDatabase converts JSON to TEXT for SQLite', () {
      expect(
        SQLType.toSqlForDatabase('json', DatabaseType.sqlite),
        'TEXT',
      );
      expect(
        SQLType.toSqlForDatabase('jsonb', DatabaseType.sqlite),
        'TEXT',
      );
    });

    test('toSqlForDatabase keeps JSON for PostgreSQL', () {
      expect(
        SQLType.toSqlForDatabase('json', DatabaseType.postgresql),
        'JSON',
      );
      expect(
        SQLType.toSqlForDatabase('jsonb', DatabaseType.postgresql),
        'JSONB',
      );
    });

    test('convertTypeForDatabase converts JSON to TEXT for SQLite', () {
      expect(
        SQLType.convertTypeForDatabase('JSON', DatabaseType.sqlite),
        'TEXT',
      );
      expect(
        SQLType.convertTypeForDatabase('JSONB', DatabaseType.sqlite),
        'TEXT',
      );
    });

    test('convertTypeForDatabase keeps other types unchanged', () {
      expect(
        SQLType.convertTypeForDatabase('INTEGER', DatabaseType.sqlite),
        'INTEGER',
      );
      expect(
        SQLType.convertTypeForDatabase('TEXT', DatabaseType.postgresql),
        'TEXT',
      );
    });
  });
}
