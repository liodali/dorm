# DormQL MySQL Example

This example demonstrates how to use DormQL with MySQL database.

## Prerequisites

- Dart SDK 3.10.0 or higher
- MySQL 5.7+ or MariaDB 10+
- Podman or Docker (for running MySQL container)

## Running MySQL with Podman

### Start MySQL Container

```bash
# Using Podman
podman run -d \
  --name mysql-dorm \
  -e MYSQL_ROOT_PASSWORD=PASSWORD \
  -e MYSQL_DATABASE=mydb \
  -p 3306:3306 \
  mysql:8.0

# Or using Docker
docker run -d \
  --name mysql-dorm \
  -e MYSQL_ROOT_PASSWORD=PASSWORD \
  -e MYSQL_DATABASE=mydb \
  -p 3306:3306 \
  mysql:8.0
```

### Verify MySQL is Running

```bash
# Check container status
podman ps
# or
docker ps

# Connect to MySQL
podman exec -it mysql-dorm mysql -uroot -prootpassword mydb
# or
docker exec -it mysql-dorm mysql -uroot -prootpassword mydb
```

### Stop and Remove Container

```bash
# Stop container
podman stop mysql-dorm
# or
docker stop mysql-dorm

# Remove container
podman rm mysql-dorm
# or
docker rm mysql-dorm
```

## Running the Example

1. **Install dependencies:**

   ```bash
   dart pub get
   ```

2. **Generate ORM code:**

   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

3. **Run the example:**
   ```bash
   dart run bin/main.dart
   ```

## Database Configuration

The database configuration is defined in `lib/src/db.dart`:

```dart
@Db(
  config: DbConfig.mysql(
    host: 'localhost',
    port: 3306,
    database: 'mydb',
    username: 'root',
    password: 'rootpassword',
  ),
  // ... other config
)
```

## Features Demonstrated

- ✅ MySQL connection setup
- ✅ Entity definitions with relationships
- ✅ Schema generation and migrations
- ✅ CRUD operations
- ✅ One-to-Many relationships (User → Posts)
- ✅ Many-to-Many relationships (User ↔ Products)
- ✅ LINQ-style queries
- ✅ Transaction support

## Entities

### UserEntity

- Fields: id, name, email, address, phoneNumber
- Relationships: posts (OneToMany), products (ManyToMany)

### PostEntity

- Fields: id, title, content, userId
- Relationships: user (ManyToOne)

### ProductEntity

- Fields: id, name, description, category, price
- Relationships: users (ManyToMany)

## Alternative MySQL Configurations

### Using MariaDB

```bash
podman run -d \
  --name mariadb-dorm \
  -e MYSQL_ROOT_PASSWORD=rootpassword \
  -e MYSQL_DATABASE=mydb \
  -p 3306:3306 \
  mariadb:10.11
```

### Using Percona Server

```bash
podman run -d \
  --name percona-dorm \
  -e MYSQL_ROOT_PASSWORD=rootpassword \
  -e MYSQL_DATABASE=mydb \
  -p 3306:3306 \
  percona:8.0
```

### With Persistent Storage

```bash
podman run -d \
  --name mysql-dorm \
  -e MYSQL_ROOT_PASSWORD=rootpassword \
  -e MYSQL_DATABASE=mydb \
  -p 3306:3306 \
  -v mysql-data:/var/lib/mysql \
  mysql:8.0
```

## Troubleshooting

### Connection Refused

- Ensure MySQL container is running: `podman ps`
- Check port mapping: `podman port mysql-dorm`
- Verify MySQL is ready: `podman logs mysql-dorm`

### Authentication Issues

- Ensure password matches in both container and `db.dart`
- For MySQL 8.0+, authentication plugin is `caching_sha2_password` (supported by mysql_client_plus)

### Schema Validation Errors

- Drop and recreate database if schema changed significantly
- Run migrations to update schema incrementally
