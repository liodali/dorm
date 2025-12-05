import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

/// Quick fix that adds targetEntity parameter to @OneToOne annotation.
class AddOneToOneTargetFix extends ResolvedCorrectionProducer {
  static const _addTargetKind = FixKind(
    'dormql.fix.addOneToOneTarget',
    DartFixKindPriority.standard,
    "Add targetEntity parameter to @OneToOne",
  );

  AddOneToOneTargetFix({required super.context});

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _addTargetKind;

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

    // Find the @OneToOne annotation
    Annotation? oneToOneAnnotation;
    for (final annotation in fieldDecl.metadata) {
      final name = annotation.name;
      if (name is SimpleIdentifier && name.name == 'OneToOne') {
        oneToOneAnnotation = annotation;
        break;
      }
    }

    if (oneToOneAnnotation == null) return;

    // Get the field type name to suggest as target
    final fieldType = fieldDecl.fields.type;
    String? targetEntityName;
    if (fieldType is NamedType) {
      targetEntityName = fieldType.element?.name;
    }

    if (targetEntityName == null) return;

    await builder.addDartFileEdit(file, (builder) {
      // If annotation has no arguments, add them
      if (oneToOneAnnotation!.arguments == null) {
        builder.addSimpleInsertion(
          oneToOneAnnotation.name.end,
          '(targetEntity: $targetEntityName)',
        );
      } else {
        // Add targetEntity to existing arguments
        final args = oneToOneAnnotation.arguments!;
        builder.addSimpleInsertion(
          args.rightParenthesis.offset,
          'targetEntity: $targetEntityName, ',
        );
      }
    });
  }
}

/// Quick fix that removes mappedBy from @OneToOne on the owning side.
class RemoveOneToOneMappedByFix extends ResolvedCorrectionProducer {
  static const _removeMappedByKind = FixKind(
    'dormql.fix.removeOneToOneMappedBy',
    DartFixKindPriority.standard,
    "Remove mappedBy from @OneToOne (owning side)",
  );

  RemoveOneToOneMappedByFix({required super.context});

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _removeMappedByKind;

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

    // Find the @OneToOne annotation
    Annotation? oneToOneAnnotation;
    for (final annotation in fieldDecl.metadata) {
      final name = annotation.name;
      if (name is SimpleIdentifier && name.name == 'OneToOne') {
        oneToOneAnnotation = annotation;
        break;
      }
    }

    if (oneToOneAnnotation == null) return;

    final args = oneToOneAnnotation.arguments?.arguments;
    if (args == null) return;

    // Find and remove the mappedBy argument
    for (final arg in args) {
      if (arg is NamedExpression && arg.name.label.name == 'mappedBy') {
        await builder.addDartFileEdit(file, (builder) {
          // Remove the entire mappedBy argument including comma and spaces
          builder.addDeletion(range.node(arg));
        });
        return;
      }
    }
  }
}
