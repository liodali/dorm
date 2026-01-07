## 0.7.0

### Upcoming

- ⏳ cassandra support

## 0.6.0

### Upcoming

- ⏳ improve select query API
- ⏳ add sql built-in functions
- ⏳ improve raw query API

## 0.5.0

### Upcoming

- ⏳ Support SSL for postgresql connection
- ⏳ Support SSL for mysql connection
- ⏳ Detect SQL injection in raw queries
- ⏳ improve support for stored procedures
- ⏳ Add support for custom types

## 0.4.0

### Completed

- ✅ Add type-safe column references via `Entity.columns.fieldName` - Use `ColumnMetadata` objects for compile-time type safety
- ✅ Add DTO generator - Automatically generates DTOs for all entities, excluding relationship fields
- ✅ Add `selectColumns()` method to QueryBuilder for type-safe column selection
- ✅ Add `columnsMeta()` method to SelectBuilder for backward compatibility
- ✅ Add MySQL package support using `mysql_client_plus` (no SSL mode)
- ✅ Add YAML/TOML configuration file support for database connections
- ✅ Add `DatabaseConfigLoader` class with auto-detection of `db_configuration.yml` or `db_configuration.toml`
- ✅ Support environment-based configuration (development, production, test, etc.)
- ✅ Support environment variable expansion with `${VAR_NAME}` syntax
- ✅ Add `ConfigurationException` for configuration errors
- ✅ Integrate `DatabaseConfigLoader` into generated `setup()` method with `environment` and `configPath` parameters

### Upcoming

- ⏳ Add tests for migration and schema validation

## 0.3.0

### Completed

- ✅ Add `dormql_analyzer_plugin` - Static analysis plugin for DormQL annotations
- ✅ Entity validation rules (missing ID, multiple IDs, ID type mismatch)
- ✅ `@OneToOne` relationship validation (target entity, mappedBy checks)
- ✅ Quick fixes for common issues (add ID field, remove nullable marker)
- ✅ Improved `@OneToMany` relationship - auto-resolve FK from target entity's `@ManyToOne`
- ✅ Improved `@OneToMany` relationship - auto-resolve target table from `@Entity` annotation
- ✅ Remove `targetTable` parameter from `@OneToMany` (now auto-resolved)
- ✅ Remove `foreignKey` parameter from `@OneToMany` (now auto-resolved from target's `@ManyToOne`)
- ✅ Better error messages when FK cannot be resolved
- ✅ Removed `dbType` from `@Entity` (database type is now derived from `@Db`'s `DbConfig`)
- ✅ Extended `@Id` to support `autoIncrement` and `strategy` (including `IDStrategy.uuid`) with database-specific auto-increment handling

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
