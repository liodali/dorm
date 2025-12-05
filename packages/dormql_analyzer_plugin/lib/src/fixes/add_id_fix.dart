import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

/// Quick fix that adds an @Id annotated field to an entity class.
class AddIdFix extends ResolvedCorrectionProducer {
  static const _addIdKind = FixKind(
    'dormql.fix.addId',
    DartFixKindPriority.standard,
    "Add '@Id() int id;' field",
  );

  AddIdFix({required super.context});

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _addIdKind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final node = this.node;

    // Find the class declaration
    ClassDeclaration? classDecl;
    if (node is ClassDeclaration) {
      classDecl = node;
    } else if (node.parent is ClassDeclaration) {
      classDecl = node.parent as ClassDeclaration;
    }

    if (classDecl == null) return;

    // Find the position to insert the field (after the opening brace)
    final leftBracket = classDecl.leftBracket;

    await builder.addDartFileEdit(file, (builder) {
      // Insert after the opening brace with proper formatting
      builder.addSimpleInsertion(leftBracket.end, '\n  @Id()\n  int id;\n');
    });
  }
}

/// Quick fix that adds an @Id.uuid() annotated field to an entity class.
class AddUuidIdFix extends ResolvedCorrectionProducer {
  static const _addUuidIdKind = FixKind(
    'dormql.fix.addUuidId',
    DartFixKindPriority.standard - 1,
    "Add '@Id.uuid() String id;' field",
  );

  AddUuidIdFix({required super.context});

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _addUuidIdKind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final node = this.node;

    // Find the class declaration
    ClassDeclaration? classDecl;
    if (node is ClassDeclaration) {
      classDecl = node;
    } else if (node.parent is ClassDeclaration) {
      classDecl = node.parent as ClassDeclaration;
    }

    if (classDecl == null) return;

    // Find the position to insert the field (after the opening brace)
    final leftBracket = classDecl.leftBracket;

    await builder.addDartFileEdit(file, (builder) {
      // Insert after the opening brace with proper formatting
      builder.addSimpleInsertion(
        leftBracket.end,
        '\n  @Id.uuid()\n  String id;\n',
      );
    });
  }
}

/// Quick fix that changes @Id() to @Id.uuid() when field is String but not using UUID.
/// This is for the autoIncrement type mismatch error when String is used with autoIncrement.
class ChangeToUuidFix extends ResolvedCorrectionProducer {
  static const _changeToUuidKind = FixKind(
    'dormql.fix.changeToUuid',
    DartFixKindPriority.standard,
    "Change to '@Id.uuid()' for String type",
  );

  ChangeToUuidFix({required super.context});

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _changeToUuidKind;

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

    // Find the @Id annotation
    Annotation? idAnnotation;
    for (final annotation in fieldDecl.metadata) {
      final name = annotation.name;
      if (name is SimpleIdentifier && name.name == 'Id') {
        idAnnotation = annotation;
        break;
      } else if (name is PrefixedIdentifier && name.prefix.name == 'Id') {
        // Already using a named constructor like @Id.uuid()
        return;
      }
    }

    if (idAnnotation == null) return;

    await builder.addDartFileEdit(file, (builder) {
      // Replace the entire @Id annotation with @Id.uuid()
      builder.addSimpleReplacement(range.node(idAnnotation!), '@Id.uuid()');
    });
  }
}
