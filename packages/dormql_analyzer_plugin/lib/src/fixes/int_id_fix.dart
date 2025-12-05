import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

/// Quick fix that changes the field type to int when autoIncrement is true but type is not int.
/// For example: @Id(autoIncrement: true) String id; -> @Id(autoIncrement: true) int id;
class ChangeToIntTypeFix extends ResolvedCorrectionProducer {
  static const _changeToIntKind = FixKind(
    'dormql.fix.changeToIntType',
    DartFixKindPriority.standard,
    "Change type to 'int' for autoIncrement",
  );

  ChangeToIntTypeFix({required super.context});

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _changeToIntKind;

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

    // Get the type node
    final typeNode = fieldDecl.fields.type;
    if (typeNode == null) return;

    await builder.addDartFileEdit(file, (builder) {
      // Replace the type with int
      builder.addSimpleReplacement(range.node(typeNode), 'int');
    });
  }
}
