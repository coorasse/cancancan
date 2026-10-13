require_relative '../sti_detector'

# this class is responsible for detecting sti classes and creating new rules for the
# relevant subclasses, using the inheritance_column as a merger
module CanCan
  module ModelAdapters
    class StiNormalizer
      class << self
        def normalize(model_class, rules)
          return unless defined?(ActiveRecord::Base)

          rules.replace(rules.flat_map { |rule| normalized_rules(model_class, rule) })
        end

        private

        # The rules for the subclasses take the place of the original rule, so their precedence is kept.
        # The original rule is kept only for its other subjects that match the model.
        def normalized_rules(model_class, rule)
          sti_subjects = rule.subjects.select { |subject| StiDetector.sti_class?(subject) }
          return [rule] if sti_subjects.empty?

          subclass_rules = sti_subjects.select { |subject| subject <= model_class || model_class <= subject }
                                       .map { |subject| build_rule_for_subclass(rule, subject) }
          [*rule_for_other_subjects(model_class, rule, rule.subjects - sti_subjects), *subclass_rules]
        end

        def rule_for_other_subjects(model_class, rule, subjects)
          return unless subjects.include?(:all) || SubjectClassMatcher.matches_subject_class?(subjects, model_class)

          CanCan::Rule.new(rule.base_behavior, rule.actions, subjects, rule.attributes, rule.conditions, rule.block)
        end

        # create a new rule for the subclass and its descendants that links on the inheritance_column
        def build_rule_for_subclass(rule, subject)
          sti_names = [subject, *subject.descendants].map(&:sti_name)
          sti_conditions = { subject.inheritance_column => sti_names.one? ? sti_names.first : sti_names }
          new_rule_conditions =
            if rule.with_scope?
              rule.conditions.where(sti_conditions)
            else
              rule.conditions.merge(sti_conditions)
            end

          CanCan::Rule.new(rule.base_behavior, rule.actions, subject.superclass,
                           new_rule_conditions, rule.block)
        end
      end
    end
  end
end
