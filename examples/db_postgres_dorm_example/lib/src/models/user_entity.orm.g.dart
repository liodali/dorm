// GENERATED CODE - DO NOT MODIFY BY HAND
// Generated code for UserEntity

import 'package:dorm/dorm.dart';
import 'user_entity.dart';

class UserEntityRepository extends Repository<UserEntity> {
  UserEntityRepository() : super('users');

  @override
  UserEntity fromRow(Map<String, dynamic> row) {
    return UserEntity(
      id: row['id'] != null ? row['id'] as int : null,
      name: row['name'] as String,
      email: row['email'] as String
    );
  }

  @override
  Map<String, dynamic> toRow(UserEntity entity) {
    return {
      'id': entity.id,
      'name': entity.name,
      'email': entity.email
    };
  }

  @override
  Future<void> loadRelationships(UserEntity entity, List<String> includes) async {
    // No relationships defined
  }
}