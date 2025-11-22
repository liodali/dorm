// GENERATED CODE - DO NOT MODIFY BY HAND
// Generated code for PostEntity


part of 'post_entity.dart';


class PostEntityRepository extends Repository<PostEntity> {
  PostEntityRepository() : super('posts');

  @override
  PostEntity fromRow(Map<String, dynamic> row) {
    return PostEntity(
      id: row['id'] != null ? row['id'] as int : null,
      title: row['title'] as String,
      content: row['content'] as String,
      userId: row['user_id'] != null ? row['user_id'] as int : null
    );
  }

  @override
  Map<String, dynamic> toRow(PostEntity entity) {
    return {
      'id': entity.id,
      'title': entity.title,
      'content': entity.content,
      'user_id': entity.userId
    };
  }

  @override
  Future<void> loadRelationships(PostEntity entity, List<String> includes) async {
    // No relationships defined
  }
}