## 0.3.0

### Upcoming

- ⏳ Integrate YAML file for connection configuration and environment variables
- ⏳ Add tests for migration and schema validation
- ⏳ Add MySQL package support

## 0.2.0

### Completed

- ✅ Add `@OneToOne` relationship annotation
- ✅ Add `@PrimaryKey`, `@Unique`, `@ForeignKeyConstraint`, `@Check` annotations
- ✅ Add validation for annotation column references (fails if column doesn't exist)
- ✅ Add Schema to SQL extensions (`toCreateTableSql()`, `toCreateIndexSql()`, etc.)
- ✅ Add `SchemaManager` for executing schema operations
- ✅ Add migration helper methods (`createTable`, `addColumn`, `createIndex`, etc.)
- ✅ Add `createSchema()` method to generated database class
- ✅ Add `autoCreateSchema` parameter to `setup()` method
- ✅ All schema operations use `IF NOT EXISTS` / `IF EXISTS` for idempotency
- ✅ Schema now generated as extension on entity (`EntityNameSchema.schema`)
- ✅ Database class references entity schemas (no duplication)
- ✅ Build order: entity → schema → db (proper dependency chain)
- ✅ Add `generateSql` parameter to `@Db` annotation
- ✅ Generate SQL files at `.dart_tool/dorm/<db_name>.sql` on build
- ✅ Versioned SQL files: `<db_name>_v<version>.sql`


## 0.1.0

### Completed

- ✅ Bring back `part of` directive in `.orm.g.dart` files for entity files
- ✅ Create `@Db` annotation and db generator for database class generation
- ✅ Generate repository extensions with singleton pattern
- ✅ Link schema generation to database level (not entity level)
- ✅ Add schema hash for change detection
- ✅ Fail initialization if schema changed but migration version not bumped
- ✅ Integrate `DatabaseMigration` with `MigrationRunner`

### Breaking Changes

- `DatabaseMigration.Up()` renamed to `DatabaseMigration.up()`
- `DatabaseMigration.Down()` renamed to `DatabaseMigration.down()`
- Schema is now generated at database level, not entity level

## 0.0.1

- Initial version.
