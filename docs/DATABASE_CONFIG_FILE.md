# Database Configuration File

DormQL supports loading database configuration from YAML or TOML files, with environment-based configuration and environment variable expansion.

## Quick Start

1. Create a `db_configuration.yml` file in your project root:

```yaml
environments:
  development:
    type: postgresql
    host: localhost
    port: 5432
    database: myapp_dev
    username: postgres
    password: secret

  production:
    type: postgresql
    host: ${DB_HOST}
    port: 5432
    database: ${DB_NAME}
    username: ${DB_USER}
    password: ${DB_PASSWORD}
    useSSL: true

  test:
    type: sqlite
    filePath: ":memory:"
```

2. Load configuration in your code:

```dart
import 'package:dormql/dorm.dart';

void main() async {
  final db = Database();

  // Option 1: Use environment parameter (recommended)
  await db.setup(environment: 'development');

  // Option 2: Use environment with custom config path
  await db.setup(
    environment: 'production',
    configPath: 'config/database.yml',
  );

  // Option 3: Load config manually
  final config = DatabaseConfigLoader().load('development');
  await db.setup(config: config);

  // Option 4: Use DatabaseConfig directly
  await db.setup(
    config: DatabaseConfig.postgresql(
      host: 'localhost',
      port: 5432,
      database: 'mydb',
      username: 'user',
      password: 'pass',
    ),
  );
}
```

## File Locations

The loader automatically searches for configuration files in these locations (in order):

1. Project root: `db_configuration.yml`, `db_configuration.yaml`, `db_configuration.toml`
2. `config/` directory
3. `lib/` directory

You can also specify an explicit path:

```dart
final loader = DatabaseConfigLoader(configPath: '/path/to/my_config.yml');
final config = loader.load('production');
```

## Supported Formats

### YAML (.yml, .yaml)

```yaml
environments:
  development:
    type: postgresql
    host: localhost
    port: 5432
    database: myapp_dev
    username: postgres
    password: secret
    useSSL: false
    maxConnections: 10
    connectionTimeoutSeconds: 30
```

### TOML (.toml)

```toml
[environments.development]
type = "postgresql"
host = "localhost"
port = 5432
database = "myapp_dev"
username = "postgres"
password = "secret"
useSSL = false
maxConnections = 10
connectionTimeoutSeconds = 30
```

## Configuration Options

| Option                     | Type   | Required | Default | Description                                     |
| -------------------------- | ------ | -------- | ------- | ----------------------------------------------- |
| `type`                     | string | Yes      | -       | Database type: `postgresql`, `mysql`, `sqlite`  |
| `host`                     | string | No\*     | -       | Database host                                   |
| `port`                     | int    | No\*     | -       | Database port                                   |
| `database`                 | string | No\*     | -       | Database name                                   |
| `username`                 | string | No\*     | -       | Database username                               |
| `password`                 | string | No\*     | -       | Database password                               |
| `filePath`                 | string | No\*\*   | -       | SQLite file path (use `:memory:` for in-memory) |
| `useSSL`                   | bool   | No       | `false` | Enable SSL connection                           |
| `maxConnections`           | int    | No       | `10`    | Maximum connection pool size                    |
| `connectionTimeoutSeconds` | int    | No       | `30`    | Connection timeout in seconds                   |
| `additionalParams`         | map    | No       | -       | Additional database-specific parameters         |

\* Required for PostgreSQL and MySQL  
\*\* Required for SQLite

## Environment Variables

Use `${VAR_NAME}` syntax to reference environment variables:

```yaml
environments:
  production:
    type: postgresql
    host: ${DB_HOST}
    port: 5432
    database: ${DB_NAME}
    username: ${DB_USER}
    password: ${DB_PASSWORD}
```

To disable environment variable expansion:

```dart
final config = loader.load('production', expandEnvVars: false);
```

## Database Type Aliases

The following aliases are supported for database types:

| Type       | Aliases                        |
| ---------- | ------------------------------ |
| PostgreSQL | `postgresql`, `postgres`, `pg` |
| MySQL      | `mysql`, `mariadb`             |
| SQLite     | `sqlite`, `sqlite3`            |

## API Reference

### DatabaseConfigLoader

```dart
// Create loader with auto-detection
final loader = DatabaseConfigLoader();

// Create loader with explicit path
final loader = DatabaseConfigLoader(configPath: 'config/database.yml');

// Load configuration
final config = loader.load('development');

// Load asynchronously
final config = await loader.loadAsync('production');

// Get available environments
final envs = loader.getAvailableEnvironments(); // ['development', 'production', 'test']

// Check if environment exists
final exists = loader.hasEnvironment('staging'); // false

// Clear cached configuration
loader.clearCache();
```

### Static Methods

```dart
// Auto-detect configuration file
final path = DatabaseConfigLoader.detectConfigFile();

// Load directly via extension
final config = DatabaseConfigFromFile.fromFile('development');
final config = await DatabaseConfigFromFile.fromFileAsync('production');
```

## Error Handling

```dart
try {
  final config = loader.load('production');
} on ConfigurationException catch (e) {
  print('Configuration error: ${e.message}');
}
```

Common errors:

- Configuration file not found
- Missing `environments` section
- Environment not found
- Missing required fields (type, filePath for SQLite)
- Unknown database type
- Environment variable not set

## Best Practices

1. **Never commit sensitive credentials** - Use environment variables for production
2. **Use `:memory:` for tests** - Fast, isolated SQLite databases
3. **Set appropriate connection limits** - Match your server capacity
4. **Enable SSL in production** - Secure your database connections
5. **Keep configuration files out of version control** - Add to `.gitignore` if they contain secrets
