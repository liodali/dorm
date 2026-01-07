import 'dart:io';

import 'package:yaml/yaml.dart';
import 'package:toml/toml.dart';

import 'database_connection.dart';

/// Exception thrown when configuration loading fails
class ConfigurationException implements Exception {
  final String message;
  const ConfigurationException(this.message);

  @override
  String toString() => 'ConfigurationException: $message';
}

/// Supported configuration file formats
enum ConfigFormat { yaml, toml }

/// Loader for database configuration from YAML/TOML files
///
/// Supports environment-based configuration with automatic file detection.
///
/// Example YAML configuration (db_configuration.yml):
/// ```yaml
/// environments:
///   development:
///     type: postgresql
///     host: localhost
///     port: 5432
///     database: myapp_dev
///     username: postgres
///     password: secret
///     useSSL: false
///     maxConnections: 10
///     connectionTimeoutSeconds: 30
///
///   production:
///     type: postgresql
///     host: prod-db.example.com
///     port: 5432
///     database: myapp_prod
///     username: ${DB_USER}
///     password: ${DB_PASSWORD}
///     useSSL: true
///     maxConnections: 50
///
///   test:
///     type: sqlite
///     filePath: :memory:
/// ```
///
/// Example TOML configuration (db_configuration.toml):
/// ```toml
/// [environments.development]
/// type = "postgresql"
/// host = "localhost"
/// port = 5432
/// database = "myapp_dev"
/// username = "postgres"
/// password = "secret"
/// useSSL = false
/// maxConnections = 10
/// connectionTimeoutSeconds = 30
///
/// [environments.production]
/// type = "postgresql"
/// host = "prod-db.example.com"
/// port = 5432
/// database = "myapp_prod"
/// username = "${DB_USER}"
/// password = "${DB_PASSWORD}"
/// useSSL = true
/// maxConnections = 50
///
/// [environments.test]
/// type = "sqlite"
/// filePath = ":memory:"
/// ```
class DatabaseConfigLoader {
  /// Default configuration file names to search for
  static const List<String> defaultFileNames = [
    'db_configuration.yml',
    'db_configuration.yaml',
    'db_configuration.toml',
  ];

  /// Default search paths relative to project root
  static const List<String> defaultSearchPaths = [
    '', // Project root
    'config',
    'lib',
  ];

  final String? _configPath;
  final ConfigFormat? _format;
  Map<String, dynamic>? _cachedConfig;

  /// Creates a loader with optional explicit path
  ///
  /// If [configPath] is not provided, auto-detection will be used.
  /// If [format] is not provided, it will be inferred from file extension.
  DatabaseConfigLoader({String? configPath, ConfigFormat? format})
    : _configPath = configPath,
      _format = format;

  /// Load configuration for a specific environment
  ///
  /// [environment] - The environment name (e.g., 'development', 'production', 'test')
  /// [expandEnvVars] - Whether to expand environment variables in values (default: true)
  ///
  /// Throws [ConfigurationException] if configuration cannot be loaded.
  DatabaseConfig load(String environment, {bool expandEnvVars = true}) {
    final config = _loadConfigFile();
    final environments = config['environments'] as Map<String, dynamic>?;

    if (environments == null) {
      throw ConfigurationException(
        'Configuration file must contain an "environments" section',
      );
    }

    final envConfig = environments[environment] as Map<String, dynamic>?;
    if (envConfig == null) {
      final available = environments.keys.join(', ');
      throw ConfigurationException(
        'Environment "$environment" not found. Available: $available',
      );
    }

    return _parseConfig(envConfig, expandEnvVars);
  }

  /// Load configuration asynchronously
  Future<DatabaseConfig> loadAsync(
    String environment, {
    bool expandEnvVars = true,
  }) async {
    return load(environment, expandEnvVars: expandEnvVars);
  }

  /// Get all available environment names
  List<String> getAvailableEnvironments() {
    final config = _loadConfigFile();
    final environments = config['environments'] as Map<String, dynamic>?;
    return environments?.keys.toList() ?? [];
  }

  /// Check if a specific environment exists
  bool hasEnvironment(String environment) {
    final config = _loadConfigFile();
    final environments = config['environments'] as Map<String, dynamic>?;
    return environments?.containsKey(environment) ?? false;
  }

  /// Clear cached configuration (useful for reloading)
  void clearCache() {
    _cachedConfig = null;
  }

  /// Auto-detect and find configuration file
  ///
  /// Returns the path to the configuration file or null if not found.
  static String? detectConfigFile({String? basePath}) {
    final base = basePath ?? Directory.current.path;

    for (final searchPath in defaultSearchPaths) {
      for (final fileName in defaultFileNames) {
        final fullPath = searchPath.isEmpty
            ? '$base/$fileName'
            : '$base/$searchPath/$fileName';
        if (File(fullPath).existsSync()) {
          return fullPath;
        }
      }
    }
    return null;
  }

  Map<String, dynamic> _loadConfigFile() {
    if (_cachedConfig != null) {
      return _cachedConfig!;
    }

    final path = _configPath ?? detectConfigFile();
    if (path == null) {
      throw ConfigurationException(
        'No configuration file found. '
        'Create db_configuration.yml or db_configuration.toml in project root, '
        'config/, or lib/ directory.',
      );
    }

    final file = File(path);
    if (!file.existsSync()) {
      throw ConfigurationException('Configuration file not found: $path');
    }

    final content = file.readAsStringSync();
    final format = _format ?? _inferFormat(path);

    _cachedConfig = _parseFile(content, format);
    return _cachedConfig!;
  }

  ConfigFormat _inferFormat(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.toml')) {
      return ConfigFormat.toml;
    }
    return ConfigFormat.yaml;
  }

  Map<String, dynamic> _parseFile(String content, ConfigFormat format) {
    switch (format) {
      case ConfigFormat.yaml:
        return _parseYaml(content);
      case ConfigFormat.toml:
        return _parseToml(content);
    }
  }

  Map<String, dynamic> _parseYaml(String content) {
    final yaml = loadYaml(content);
    return _convertYamlToMap(yaml);
  }

  Map<String, dynamic> _parseToml(String content) {
    final toml = TomlDocument.parse(content);
    return toml.toMap();
  }

  Map<String, dynamic> _convertYamlToMap(dynamic yaml) {
    if (yaml is YamlMap) {
      return yaml.map(
        (key, value) => MapEntry(key.toString(), _convertYamlToMap(value)),
      );
    } else if (yaml is YamlList) {
      return {'_list': yaml.map(_convertYamlToMap).toList()};
    }
    return {'_value': yaml};
  }

  DatabaseConfig _parseConfig(Map<String, dynamic> config, bool expandEnvVars) {
    final typeStr = _getString(config, 'type', expandEnvVars);
    if (typeStr == null) {
      throw ConfigurationException('Database type is required');
    }

    final type = _parseDatabaseType(typeStr);

    switch (type) {
      case DatabaseType.sqlite:
        final filePath = _getString(config, 'filePath', expandEnvVars);
        if (filePath == null) {
          throw ConfigurationException('filePath is required for SQLite');
        }
        return DatabaseConfig.sqlite(filePath: filePath);

      case DatabaseType.postgresql:
      case DatabaseType.mysql:
        return DatabaseConfig(
          type: type,
          host: _getString(config, 'host', expandEnvVars),
          port: _getInt(config, 'port'),
          database: _getString(config, 'database', expandEnvVars),
          username: _getString(config, 'username', expandEnvVars),
          password: _getString(config, 'password', expandEnvVars),
          useSSL: _getBool(config, 'useSSL') ?? false,
          maxConnections: _getInt(config, 'maxConnections') ?? 10,
          connectionTimeout: Duration(
            seconds: _getInt(config, 'connectionTimeoutSeconds') ?? 30,
          ),
          additionalParams: _getMap(config, 'additionalParams'),
        );
    }
  }

  DatabaseType _parseDatabaseType(String type) {
    switch (type.toLowerCase()) {
      case 'postgresql':
      case 'postgres':
      case 'pg':
        return DatabaseType.postgresql;
      case 'mysql':
      case 'mariadb':
        return DatabaseType.mysql;
      case 'sqlite':
      case 'sqlite3':
        return DatabaseType.sqlite;
      default:
        throw ConfigurationException(
          'Unknown database type: $type. '
          'Supported types: postgresql, mysql, sqlite',
        );
    }
  }

  String? _getString(
    Map<String, dynamic> config,
    String key,
    bool expandEnvVars,
  ) {
    final value = config[key];
    if (value == null) return null;
    final str = value.toString();
    return expandEnvVars ? _expandEnvironmentVariables(str) : str;
  }

  int? _getInt(Map<String, dynamic> config, String key) {
    final value = config[key];
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  bool? _getBool(Map<String, dynamic> config, String key) {
    final value = config[key];
    if (value == null) return null;
    if (value is bool) return value;
    final str = value.toString().toLowerCase();
    return str == 'true' || str == '1' || str == 'yes';
  }

  Map<String, dynamic>? _getMap(Map<String, dynamic> config, String key) {
    final value = config[key];
    if (value == null) return null;
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  /// Expand environment variables in the format ${VAR_NAME}
  String _expandEnvironmentVariables(String value) {
    final regex = RegExp(r'\$\{([^}]+)\}');
    return value.replaceAllMapped(regex, (match) {
      final varName = match.group(1)!;
      final envValue = Platform.environment[varName];
      if (envValue == null) {
        throw ConfigurationException(
          'Environment variable "$varName" is not set',
        );
      }
      return envValue;
    });
  }
}

/// Extension to create DatabaseConfig from configuration file
extension DatabaseConfigFromFile on DatabaseConfig {
  /// Load configuration from file for a specific environment
  ///
  /// [environment] - The environment name (e.g., 'development', 'production')
  /// [configPath] - Optional explicit path to configuration file
  static DatabaseConfig fromFile(
    String environment, {
    String? configPath,
    bool expandEnvVars = true,
  }) {
    final loader = DatabaseConfigLoader(configPath: configPath);
    return loader.load(environment, expandEnvVars: expandEnvVars);
  }

  /// Load configuration asynchronously
  static Future<DatabaseConfig> fromFileAsync(
    String environment, {
    String? configPath,
    bool expandEnvVars = true,
  }) async {
    final loader = DatabaseConfigLoader(configPath: configPath);
    return loader.loadAsync(environment, expandEnvVars: expandEnvVars);
  }
}
