import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'fixes/add_id_fix.dart';
import 'fixes/int_id_fix.dart';
import 'fixes/onetoone_fixes.dart';
import 'fixes/remove_nullable_fix.dart';
import 'rules/entity/column_type_mismatch_rule.dart';
import 'rules/entity/id_nullable_rule.dart';
import 'rules/entity/id_primarykey_conflict_rule.dart';
import 'rules/entity/id_type_mismatch_rule.dart';
import 'rules/entity/missing_id_rule.dart';
import 'rules/entity/multiple_ids_rule.dart';
import 'rules/relationship/one_to_one_rules.dart';

/// DormQL Analyzer Plugin for validating DormQL annotations.
///
/// This plugin provides static analysis for:
/// - @Entity classes and @Id type validation
/// - Relationship annotations (@OneToOne, @OneToMany, @ManyToOne, @ManyToMany)
/// - @Db configuration and schema version checking
final class DormQLAnalyzerPlugin extends Plugin {
  @override
  String get name => 'DormQL Analyzer Plugin';

  @override
  void register(PluginRegistry registry) {
    // Entity validation rules
    registry.registerWarningRule(MissingIdRule());
    registry.registerWarningRule(MultipleIdsRule());
    registry.registerWarningRule(IdTypeMismatchRule());
    registry.registerWarningRule(IdPrimaryKeyConflictRule());
    registry.registerWarningRule(IdNullableRule());
    registry.registerWarningRule(ColumnTypeMismatchRule());

    // Relationship validation rules
    registry.registerWarningRule(OneToOneRules());

    // Quick fixes for missing ID
    registry.registerFixForRule(MissingIdRule.code, AddIdFix.new);
    registry.registerFixForRule(MissingIdRule.code, AddUuidIdFix.new);

    // Quick fixes for ID type mismatch
    // When autoIncrement is true but type is String -> offer to change to int OR change to uuid
    registry.registerFixForRule(
      IdTypeMismatchRule.autoIncrementCode,
      ChangeToIntTypeFix.new,
    );
    registry.registerFixForRule(
      IdTypeMismatchRule.autoIncrementCode,
      ChangeToUuidFix.new,
    );

    // Quick fixes for nullable ID
    registry.registerFixForRule(IdNullableRule.code, RemoveNullableFix.new);

    // Quick fixes for @OneToOne
    registry.registerFixForRule(
      OneToOneRules.missingTargetCode,
      AddOneToOneTargetFix.new,
    );
    registry.registerFixForRule(
      OneToOneRules.invalidMappedByCode,
      RemoveOneToOneMappedByFix.new,
    );
  }
}
