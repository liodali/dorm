# Code Generation Output Configuration

## Generated File Locations

The DORM code generator outputs files **in the same directory** as the source entity files (standard build_runner behavior).

### Entity Files → Repository Files

Entity files can be located anywhere under `lib/`, and the generator will create corresponding repository files **in the same directory**:

| Entity File Location               | Generated Repository Location            | Import in Generated File        |
| ---------------------------------- | ---------------------------------------- | ------------------------------- |
| `lib/src/user_entity.dart`         | `lib/src/user_entity.orm.g.dart`         | `import 'user_entity.dart';`    |
| `lib/src/models/post_entity.dart`  | `lib/src/models/post_entity.orm.g.dart`  | `import 'post_entity.dart';`    |
| `lib/entities/product_entity.dart` | `lib/entities/product_entity.orm.g.dart` | `import 'product_entity.dart';` |

### Directory Structure

```
lib/
└── src/
    └── models/
        ├── user_entity.dart
        ├── user_entity.orm.g.dart    # Generated repository
        ├── post_entity.dart
        └── post_entity.orm.g.dart    # Generated repository
```

### How It Works

1. **Entity files** must be annotated with `@Entity` (filename and location don't matter)
2. **Generated files** are placed in the **same directory** as the source file
3. **All fields** are automatically included unless marked with `@Ignore` or relationship annotations
4. **Imports** use simple relative imports (same directory)

### Using Generated Repositories

In your application code, import repositories from their generated locations:

```dart
// Import from the same directory as the entity
import 'package:your_package/src/models/user_entity.orm.g.dart';
import 'package:your_package/src/models/post_entity.orm.g.dart';

final userRepo = UserEntityRepository();
final postRepo = PostEntityRepository();
```

### Build Configuration

The `build.yaml` in your project controls which files are processed:

```yaml
targets:
  $default:
    builders:
      dorm|entity:
        enabled: true
```

### Running Code Generation

Generate repository files with:

```bash
dart run build_runner build
```

Or watch for changes:

```bash
dart run build_runner watch
```

### Version Control

**Generated files in `lib/db_gen/` should be committed to version control** since they are source files, not build artifacts.

Add to `.gitignore`:

```
# Build artifacts
.dart_tool/
build/

# Keep generated source files
!lib/db_gen/
```

## Migration Files

Migration files will be handled separately via CLI (coming soon).
