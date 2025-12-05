# ID Strategy Improvements - Implementation Summary

## Overview

Enhanced the DormQL generator to properly utilize the new `IDStrategy` enum in the `@Id` annotation. The improvements include:

- Type-safe ID strategy validation
- Database-specific SQL generation based on strategy
- Build-time error detection for invalid configurations
- Full compatibility with existing `@PrimaryKey` annotation

## Changes Made

### 1. New File: `id_strategy_helper.dart`

**Location**: `/lib/tool/id_strategy_helper.dart`

A comprehensive utility class for ID strategy handling with the following methods:

#### Core Methods

- **`extractIdStrategy(ElementAnnotation?)`** - Extracts the ID strategy from @Id annotation
  - Supports named constructors: `Id.postgres()`, `Id.mysql()`, `Id.sqlite()`, `Id.uuid()`
  - Supports strategy parameter in default constructor
- **`getIdStrategySQL(IDStrategy, DatabaseType)`** - Returns database-specific SQL for the strategy

  - PostgreSQL: SERIAL, BIGSERIAL, UUID DEFAULT gen_random_uuid()
  - MySQL: AUTO_INCREMENT, CHAR(36) for UUID
  - SQLite: AUTOINCREMENT, TEXT for UUID

- **`getBigIdStrategySQL(IDStrategy, DatabaseType)`** - Returns big version of strategy SQL
  - For big integer primary keys (BigInt type)

#### Validation Methods

- **`validateIdStrategyForType(IDStrategy, DartType)`** - Validates strategy against field type

  - **UUID strategy**: Only works with `String` type
  - **AutoIncrement strategies**: Only work with `int` or `BigInt` types
  - Returns descriptive error message if invalid

- **`validateIdAndPrimaryKeyConflict(ElementAnnotation?, ElementAnnotation?)`** - Ensures @Id and @Column(primaryKey: true) aren't used together
  - Prevents conflicting primary key definitions

#### Helper Methods

- **`isAutoIncrementStrategy(IDStrategy)`** - Checks if strategy is auto-increment
- **`isUuidStrategy(IDStrategy)`** - Checks if strategy is UUID
- **`getStrategyLabel(IDStrategy)`** - Returns display label for strategy

### 2. Updated: `entity_generator.dart`

**Changes**:

- Added import for `IdStrategyHelper`
- Added validation in field processing loop:
  - Validates @Id and @Column(primaryKey: true) conflict
  - Validates ID strategy against field type
  - Throws `InvalidGenerationSourceError` with descriptive message on validation failure
- Captures `idAnnotation` in field metadata for later use

**Error Messages**:

```
"Cannot use both @Id and @Column(primaryKey: true) on the same field..."
"UUID strategy can only be used with String type, but field is {type}"
"AutoIncrement strategy can only be used with int or BigInt type, but field is {type}"
```

### 3. Updated: `db_generator.dart`

**Changes**:

- Added import for `IdStrategyHelper` and `DatabaseType`
- Updated `_ColumnInfo` class to include `idAnnotation` field
- Updated `_extractColumnsFromEntity()` to capture ID annotation
- Updated `_generateCreateTableSql()` to use ID strategy for SQL generation:
  - Extracts strategy from annotation
  - Uses `IdStrategyHelper.getIdStrategySQL()` or `getBigIdStrategySQL()`
  - Falls back to default behavior if no strategy found
- Added `_dialectToDatabaseType()` helper to convert dialect string to DatabaseType enum

**SQL Generation Examples**:

```dart
// PostgreSQL with UUID strategy
id UUID DEFAULT gen_random_uuid() PRIMARY KEY

// MySQL with AutoIncrement strategy
id INT AUTO_INCREMENT PRIMARY KEY

// SQLite with AutoIncrement strategy
id INTEGER PRIMARY KEY AUTOINCREMENT
```

### 4. Updated: `migration_generator.dart`

**Changes**:

- Added imports for `IdStrategyHelper`
- Updated `_ColumnInfo` class to include `idAnnotation` field
- Updated `_extractColumnsFromEntity()` to:
  - Capture ID annotation
  - Use ID strategy to determine SQL type for primary keys
- Added `_idStrategyToSqlType()` method to map strategy to SQL type string
  - Maps strategies to appropriate SQLType enum values

**Strategy to SQL Type Mapping**:

```dart
IDStrategy.serial → 'SERIAL'
IDStrategy.autoIncrement → 'SERIAL' (int) or 'BIGSERIAL' (BigInt)
IDStrategy.autoIncrementSqlite → 'AUTOINCREMENT'
IDStrategy.uuid → 'UUID'
```

## Type Restrictions

### UUID Strategy

- **Allowed**: `String` type only
- **Error**: Using UUID with `int`, `BigInt`, or any other type
- **Example**:

  ```dart
  @Id.uuid()
  String? id;  // ✓ Valid (nullable)

  @Id.uuid()
  int? id;  // ✗ Build error: UUID strategy can only be used with String type
  ```

### AutoIncrement Strategies (SERIAL, AUTO_INCREMENT, AUTOINCREMENT)

- **Allowed**: `int` or `BigInt` types only
- **Error**: Using AutoIncrement with `String`, `double`, or any other type
- **Example**:

  ```dart
  @Id.postgres()
  int? id;  // ✓ Valid (uses SERIAL, nullable)

  @Id.mysql()
  BigInt? id;  // ✓ Valid (uses AUTO_INCREMENT, nullable)

  @Id.sqlite()
  String? id;  // ✗ Build error: AutoIncrement strategy can only be used with int or BigInt
  ```

### Nullability Requirement

- **Rule**: ID fields **must be nullable** by default
- **Exception**: Non-nullable IDs are only allowed when `autoIncrement: false` AND strategy is not UUID
- **Rationale**: Auto-generated IDs are assigned by the database after insertion, so the field must be nullable to represent the "not yet assigned" state
- **Example**:

  ```dart
  // ✓ Valid - nullable (recommended)
  @Id.postgres()
  int? id;

  // ✓ Valid - non-nullable with manual assignment
  @Id(autoIncrement: false, strategy: IDStrategy.serial)
  int id;

  // ✗ Build error - non-nullable with auto-generated ID
  @Id.postgres()
  int id;  // Error: ID field must be nullable unless autoIncrement is false

  // ✗ Build error - non-nullable UUID
  @Id.uuid()
  String id;  // Error: ID field must be nullable
  ```

## @Id and @PrimaryKey Compatibility

### Single-Field Primary Keys

Use `@Id` on a single field (must be nullable for auto-generated IDs):

```dart
@Entity(tableName: 'users')
class User {
  @Id.postgres()
  int? id;  // Nullable for auto-generated values
  String name;
}
```

### Composite Primary Keys

Use `@PrimaryKey` on the class:

```dart
@Entity(tableName: 'order_items')
@PrimaryKey(columns: ['order_id', 'product_id'])
class OrderItem {
  int orderId;
  int productId;
  int quantity;
}
```

### Conflict Prevention

Cannot use both `@Id` and `@PrimaryKey` on the same entity:

```dart
@Entity()
@PrimaryKey(columns: ['id'])  // ✗ Build error
class User {
  @Id()  // ✗ Conflict
  int id;
}
```

## Named Constructor Usage

### Database-Specific Constructors

```dart
// PostgreSQL (uses SERIAL)
@Id.postgres()
int id;

// MySQL (uses AUTO_INCREMENT)
@Id.mysql()
int id;

// SQLite (uses AUTOINCREMENT)
@Id.sqlite()
int id;

// UUID (uses UUID type)
@Id.uuid()
String id;
```

### Default Constructor with Strategy Parameter

```dart
@Id(strategy: IDStrategy.serial)
int id;

@Id(strategy: IDStrategy.uuid)
String id;
```

## Build-Time Error Detection

All validations occur during code generation, providing immediate feedback:

1. **Type Mismatch**: UUID with non-String types
2. **Type Mismatch**: AutoIncrement with non-int/BigInt types
3. **Annotation Conflict**: Both @Id and @Column(primaryKey: true) on same field
4. **Annotation Conflict**: Both @Id and @PrimaryKey on same entity

Errors are reported with descriptive messages pointing to the exact field/class.

## Database-Specific SQL Generation

### PostgreSQL

- `int` with SERIAL: `id SERIAL PRIMARY KEY`
- `BigInt` with SERIAL: `id BIGSERIAL PRIMARY KEY`
- `String` with UUID: `id UUID DEFAULT gen_random_uuid() PRIMARY KEY`

### MySQL

- `int` with AUTO_INCREMENT: `id INT AUTO_INCREMENT PRIMARY KEY`
- `BigInt` with AUTO_INCREMENT: `id BIGINT AUTO_INCREMENT PRIMARY KEY`
- `String` with UUID: `id CHAR(36) PRIMARY KEY`

### SQLite

- `int` with AUTOINCREMENT: `id INTEGER PRIMARY KEY AUTOINCREMENT`
- `String` with UUID: `id TEXT PRIMARY KEY`

## Backward Compatibility

- Existing code without explicit ID strategy continues to work
- Default behavior (AutoIncrement) is preserved when no strategy specified
- @PrimaryKey annotation remains unchanged and fully functional
- No breaking changes to existing APIs

## Testing Recommendations

1. **Type Validation Tests**

   - UUID with String ✓
   - UUID with int ✗
   - AutoIncrement with int ✓
   - AutoIncrement with String ✗

2. **SQL Generation Tests**

   - Verify correct SQL for each database type
   - Verify correct SQL for each strategy

3. **Conflict Detection Tests**

   - @Id + @Column(primaryKey: true) ✗
   - @Id + @PrimaryKey ✗
   - @Id alone ✓
   - @PrimaryKey alone ✓

4. **Migration Tests**
   - Verify migrations use correct strategy-based SQL
   - Verify schema detection works with strategies
