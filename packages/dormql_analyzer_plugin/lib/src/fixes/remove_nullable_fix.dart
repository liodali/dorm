import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

/// Quick fix that removes the nullable (?) from an ID field type.
class RemoveNullableFix extends ResolvedCorrectionProducer {
  static const _removeNullableKind = FixKind(
    'dormql.fix.removeNullable',
    DartFixKindPriority.standard,
    "Remove '?' from type",
  );

  RemoveNullableFix({required super.context});

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _removeNullableKind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final node = this.node;

    // Find the field declaration
    FieldDeclaration? fieldDecl;
    if (node is FieldDeclaration) {
      fieldDecl = node;
    } else if (node.parent is FieldDeclaration) {
      fieldDecl = node.parent as FieldDeclaration;
    }

    if (fieldDecl == null) return;

    final type = fieldDecl.fields.type;
    if (type is! NamedType) return;

    final question = type.question;
    if (question == null) return;

    await builder.addDartFileEdit(file, (builder) {
      // Delete the question mark
      builder.addDeletion(range.token(question));
    });
  }
}
