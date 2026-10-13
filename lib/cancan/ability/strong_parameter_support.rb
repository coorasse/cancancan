# frozen_string_literal: true

module CanCan
  module Ability
    module StrongParameterSupport
      # Returns an array of attributes suitable for use with strong parameters
      def permitted_attributes(action, subject)
        fold_attributes(action, subject) { |rule, set| apply_attributes(rule, subject, set) }
      end

      # This method returns all attributes which are explicity disallowed
      def disallowed_attributes(action, subject)
        fold_attributes(action, subject) do |rule, set|
          attributes = get_attributes(rule, subject)
          rule.base_behavior ? set.subtract(attributes) : set.merge(attributes)
        end
      end

      private

      # Reversing the relevant rules is important. Normal order means that 'cannot'
      # rules will come before 'can' rules. However, you can't remove attributes before
      # they are added. The 'reverse' is so that attributes will be added before the
      # 'cannot' rules remove them.
      def fold_attributes(action, subject, &)
        relevant_rules(action, subject)
          .reverse
          .select { |rule| rule.matches_conditions? action, subject }
          .each_with_object(Set.new, &)
          .to_a
      end

      def apply_attributes(rule, subject, set)
        if rule.base_behavior
          set.merge(get_attributes(rule, subject))
        elsif rule.attributes.empty?
          set.clear
        else
          set.subtract(rule.attributes)
        end
      end

      def get_attributes(rule, subject)
        subject = subject.values.first if subject.is_a?(Hash)
        klass = subject.is_a?(Module) ? subject : subject.class
        # empty attributes is an 'all'
        if rule.attributes.empty? && klass < ActiveRecord::Base
          klass.attribute_names.map(&:to_sym) - Array(klass.primary_key).map(&:to_sym)
        else
          rule.attributes
        end
      end
    end
  end
end
