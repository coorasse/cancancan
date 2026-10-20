# frozen_string_literal: true

module CanCan
  module Ability
    module Rules
      protected

      # Must be protected as an ability can merge with other abilities.
      # This means that an ability must expose their rules with another ability.
      def rules
        @rules ||= []
      end

      private

      def add_rule(rule)
        rules << rule
        add_rule_to_index(rule, rules.size - 1)
      end

      def rules_index
        @rules_index ||= {}
      end

      def add_rule_to_index(rule, position)
        subjects = rule.subjects.compact
        subjects << :all if subjects.empty?

        subjects.each do |subject|
          rules_index[subject] ||= []
          rules_index[subject] << position
        end
      end

      # Returns an array of Rule instances which match the action and subject
      # This does not take into consideration any hash conditions or block statements
      def relevant_rules(action, subject)
        return [] if rules.empty?

        # Actions are symbols in the rules, so 'destroy' must also match a `cannot :destroy`.
        action = action.to_sym if action.is_a?(String)

        relevant = possible_relevant_rules(subject).select do |rule|
          rule.expanded_actions ||= expand_actions(rule.actions)
          rule.relevant? action, subject
        end
        relevant.reverse!.uniq!
        optimize_order! relevant
        relevant
      end

      def possible_relevant_rules(subject)
        if subject.is_a?(Hash)
          rules
        else
          positions = rules_index.values_at(subject, *alternative_subjects(subject))
          positions.compact!
          positions.flatten!
          positions.sort!
          @rules.values_at(*positions)
        end
      end

      # Returns nil when no rule matches. A class that uses single table inheritance is checked together with
      # its subclasses, each one with the rules of its own ancestors: the check passes when any of them passes,
      # which is also when `accessible_by` can return records.
      def subject_permission(action, subject, attribute, *extra_args)
        results = sti_classes(subject).map do |klass|
          matching_rule(action, klass, attribute, *extra_args)&.base_behavior
        end
        results.compact.empty? ? nil : results.any?
      end

      def matching_rule(action, subject, attribute, *extra_args)
        relevant_rules_for_match(action, subject).detect do |rule|
          rule.matches_conditions?(action, subject, attribute, *extra_args) && rule.matches_attributes?(attribute)
        end
      end

      def sti_classes(subject)
        return [subject] unless defined?(ActiveRecord::Base) && subject.is_a?(Class) && subject < ActiveRecord::Base

        [subject, *subject.descendants.select { |klass| StiDetector.sti_class?(klass) }]
      end

      def relevant_rules_for_match(action, subject)
        rules = relevant_rules(action, subject)
        rules = rules.reject { |rule| rule.only_for_subclasses_of?(subject) } if subject.is_a?(Class)
        rules.each do |rule|
          next unless rule.only_raw_sql?

          raise Error,
                "The can? and cannot? call cannot be used with a raw sql 'can' definition. " \
                "The checking code cannot be determined for #{action.inspect} #{subject.inspect}"
        end
      end

      def relevant_rules_for_query(action, subject)
        rules = relevant_rules(action, subject).reject do |rule|
          # reject 'cannot' rules with attributes when doing queries
          rule.base_behavior == false && rule.attributes.present?
        end
        if rules.any?(&:only_block?)
          raise Error, "The accessible_by call cannot be used with a block 'can' definition." \
            "The SQL cannot be determined for #{action.inspect} #{subject.inspect}"
        end
        rules
      end

      # The can rules that give the initial attributes of a new resource, newest first. A can rule without
      # conditions allows any value, so no rule is needed, and a cannot rule without conditions hides the older rules.
      def relevant_rules_for_attributes(action, subject)
        rules = []
        relevant_rules(action, subject).each do |rule|
          if rule.conditions_empty? && rule.block.nil?
            return [] if rule.base_behavior
            break if rule.attributes.empty?
          end
          rules << rule if rule.base_behavior
        end
        rules
      end

      # Optimizes the order of the rules, so that rules with the :all subject are evaluated first.
      def optimize_order!(rules)
        first_can_in_group = -1
        rules.each_with_index do |rule, i|
          (first_can_in_group = -1) && next unless rule.base_behavior
          (first_can_in_group = i) && next if first_can_in_group == -1
          next unless rule.subjects == [:all]

          rules[i] = rules[first_can_in_group]
          rules[first_can_in_group] = rule
          first_can_in_group += 1
        end
      end
    end
  end
end
