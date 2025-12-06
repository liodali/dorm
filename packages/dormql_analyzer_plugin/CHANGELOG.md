## 0.1.1
* fix pubspec.yaml
## 0.1.0

### Initial release

- Add `dormql_analyzer_plugin` analyzer plugin for DormQL
- Entity validation rules:
  - `dormql_missing_id` – ensure every `@Entity` has a primary key (`@Id` or `@PrimaryKey`)
  - `dormql_multiple_ids` – prevent multiple `@Id` annotations in a single entity
  - `dormql_uuid_requires_string` – UUID strategy must use `String` type
  - `dormql_autoincrement_requires_int` – auto-increment strategies require `int` / `BigInt`
  - `dormql_id_nullable_not_allowed` – ID cannot be nullable when `autoIncrement: false`
  - `dormql_id_primarykey_conflict` – prevent `@Id` + `@PrimaryKey` conflicts
- `@OneToOne` relationship validation:
  - `dormql_onetoone_missing_target` – `targetEntity` is required
  - `dormql_onetoone_invalid_target` – `targetEntity` must be an `@Entity` class
  - `dormql_onetoone_mappedby_not_found` – `mappedBy` field must exist on target entity
  - `dormql_onetoone_mappedby_not_onetoone` – `mappedBy` field must also be annotated with `@OneToOne`
- Quick fixes:
  - Add `@Id() int id;` or `@Id.uuid() String id;` for missing ID
  - Remove nullable marker from ID field when not allowed
