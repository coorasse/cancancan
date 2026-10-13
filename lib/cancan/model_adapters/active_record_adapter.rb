# frozen_string_literal: true

module CanCan
  module ModelAdapters
    class ActiveRecordAdapter < AbstractAdapter
      attr_reader :compressed_rules

      def initialize(model_class, rules)
        super
        @compressed_rules = if CanCan.rules_compressor_enabled
                              RulesCompressor.new(@rules.reverse).rules_collapsed.reverse
                            else
                              @rules
                            end
        # The normalizers change the rules. Work on copies, so the rules of the ability stay the same.
        @compressed_rules = @compressed_rules.map(&:dup)
        StiNormalizer.normalize(@compressed_rules)
        ConditionsNormalizer.normalize(model_class, @compressed_rules)
      end

      class << self
        def for_class?(model_class)
          model_class <= ActiveRecord::Base
        end

        def override_condition_matching?(subject, name, _value)
          subject.class.defined_enums.include?(name.to_s)
        end

        # Enum conditions can be given as the stored values (usually integers) or as the enum names,
        # as strings or symbols.
        def matches_condition?(subject, name, value)
          values = value.nil? ? [nil] : Array.wrap(value)
          enum = subject.class.send(name.to_s.pluralize)
          attribute = subject.send(name)
          return values.include?(enum[attribute]) if values.all?(Integer)

          values.map(&:to_s).intersect?([attribute.to_s, enum[attribute].to_s])
        end

        # When belongs_to parent_id is a condition for a model,
        # we want to check the parent when testing ability for a hash {parent => model}
        def override_nested_subject_conditions_matching?(parent, child, all_conditions)
          parent_child_conditions(parent, child, all_conditions).present?
        end

        # parent_id condition can be an array of integer or one integer, we check the parent against this
        def nested_subject_matches_conditions?(parent, child, all_conditions)
          id_condition = parent_child_conditions(parent, child, all_conditions)
          return id_condition.include?(parent.id) if id_condition.is_a? Array
          return id_condition == parent.id if id_condition.is_a? Integer

          false
        end

        def parent_condition_keys(parent, child)
          [parent_condition_name(parent, child), parent_child_foreign_key(parent, child)].compact
        end

        def parent_child_conditions(parent, child, all_conditions)
          foreign_key = parent_child_foreign_key(parent, child)
          foreign_key.nil? ? nil : all_conditions[foreign_key]
        end

        # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        def parent_child_foreign_key(parent, child)
          child_class = child.is_a?(Class) ? child : child.class
          parent_class = parent.is_a?(Class) ? parent : parent.class

          foreign_key = child_class.reflect_on_all_associations(:belongs_to).find do |association|
            # Do not match on polymorphic associations or it will throw an error (klass cannot be determined)
            !association.polymorphic? && association.klass == parent.class
          end&.foreign_key&.to_sym

          # Search again in case of polymorphic associations, this time matching on the :has_many side
          # via the :as option, as well as klass
          foreign_key || parent_class.reflect_on_all_associations(:has_many).find do |has_many_assoc|
            matching_parent_child_polymorphic_association(has_many_assoc, child_class)
          end&.foreign_key&.to_sym
        end

        def matching_parent_child_polymorphic_association(parent_assoc, child_class)
          return nil unless parent_assoc.klass == child_class
          return nil if parent_assoc&.options[:as].nil?

          child_class.reflect_on_all_associations(:belongs_to).find do |child_assoc|
            # Only match this way for polymorphic associations
            child_assoc.polymorphic? && child_assoc.name == parent_assoc.options[:as]
          end
        end

        def child_association_to_parent(parent, child)
          child_class = child.is_a?(Class) ? child : child.class
          parent_class = parent.is_a?(Class) ? parent : parent.class

          association = child_class.reflect_on_all_associations(:belongs_to).find do |belongs_to_assoc|
            # Do not match on polymorphic associations or it will throw an error (klass cannot be determined)
            !belongs_to_assoc.polymorphic? && belongs_to_assoc.klass == parent.class
          end

          return association if association

          parent_class.reflect_on_all_associations(:has_many).each do |has_many_assoc|
            association ||= matching_parent_child_polymorphic_association(has_many_assoc, child_class)
          end

          association
        end

        # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        def parent_condition_name(parent, child)
          child_association_to_parent(parent, child)&.name || parent.class.name.downcase.to_sym
        end
      end

      # Returns the conditions of the rules for a database query. Normally you will not call this method
      # directly, but instead go through ModelAdditions#accessible_by.
      #
      # If there is only one "can" definition, a hash of conditions will be returned matching the one defined.
      #
      #   can :manage, User, :id => 1
      #   query(:manage, User).conditions # => { :id => 1 }
      #
      # If there are multiple "can" definitions, a SQL string will be returned to handle complex cases.
      #
      #   can :manage, User, :id => 1
      #   can :manage, User, :manager_id => 1
      #   cannot :manage, User, :self_managed => true
      #   query(:manage, User).conditions
      #   # => "("self_managed" = 't') IS NOT TRUE AND (("manager_id" = 1) OR ("id" = 1))"
      #
      def conditions
        return single_rule_conditions if single_can_rule?

        case where_conditions
        when :all then {}
        when :none then '1=0'
        else to_sql(where_conditions)
        end
      end

      def database_records
        return @model_class.none if where_conditions == :none
        return @model_class.all if where_conditions == :all

        relation = @model_class.where(where_node)
        return relation unless joins.present?

        strategy_class.new(adapter: self, relation: relation, where_conditions: where_node).execute!
      end

      # Returns the associations used in conditions for the :joins option of a search.
      # See ModelAdditions#accessible_by
      def joins
        joins_hash = {}
        @compressed_rules.reverse_each do |rule|
          deep_merge(joins_hash, rule.associations_hash)
        end
        deep_clean(joins_hash) unless joins_hash.empty?
      end

      # The conditions of a rule as an Arel node, or nil when the rule has no conditions.
      #
      # The nodes come from the Active Record internals that `where` relies on: `predicate_builder`, `where_clause`
      # and the Arel nodes. They are not public API, but have been stable since Rails 7.1 and are covered by the
      # test suite on every supported Rails version, including main.
      def rule_conditions(rule, conditions_extractor = ConditionsExtractor.new(@model_class, joins))
        if rule.with_scope?
          scope_conditions(rule.conditions)
        elsif rule.conditions.is_a?(Hash)
          hash_conditions(conditions_extractor.tableize_conditions(rule.conditions), conditions_extractor)
        elsif rule.conditions.present?
          Arel.sql(@model_class.sanitize_sql(rule.conditions))
        end
      end

      private

      # Active Record cannot find the model of an aliased table in a hash of conditions,
      # so the conditions on associations are built with the model of each table.
      def hash_conditions(conditions, conditions_extractor = nil)
        return if conditions.empty?

        Arel::Nodes::And.new(predicates(conditions, conditions_extractor))
      end

      # The conditions of a scope are used as they are. A scope with joins, a limit or other clauses that select
      # its records is used as a subquery on the primary key, so that these clauses do not apply to the records
      # of the other rules.
      def scope_conditions(scope)
        if (scope.values.keys - %i[where order references]).empty?
          scope.where_clause.ast if scope.where_clause.any?
        else
          hash_conditions(@model_class.primary_key => scope.except(:select))
        end
      end

      # The conditions of all the rules as an Arel node, or :all and :none when every record or no record
      # is accessible. The rules are folded in the order they were defined: a `can` rule adds its records
      # to the ones of the previous rules, a `cannot` rule removes its records from them.
      def where_conditions
        @where_conditions ||= begin
          conditions_extractor = ConditionsExtractor.new(@model_class, joins)
          @compressed_rules.reverse.inject(:none) do |previous, rule|
            merge_rule(previous, rule, rule_conditions(rule, conditions_extractor))
          end
        end
      end

      # A chain of ORs is grouped, so that it keeps its precedence next to the other conditions of the query.
      def where_node
        where_conditions.is_a?(Arel::Nodes::Or) ? group(where_conditions) : where_conditions
      end

      def merge_rule(previous, rule, node)
        return rule.base_behavior ? :all : :none if node.nil?

        if rule.base_behavior
          previous == :none ? node : or_conditions(node, previous)
        else
          previous == :all ? not_true(node) : and_conditions(node, previous)
        end
      end

      def and_conditions(node, previous)
        return :none if previous == :none

        Arel::Nodes::And.new([not_true(node), group(previous)])
      end

      # Consecutive `can` rules are joined in a flat chain of ORs, so that the nesting of the query only grows
      # when `can` and `cannot` rules alternate. Deeply nested conditions overflow the parser of SQLite.
      def or_conditions(node, previous)
        return :all if previous == :all

        children = previous.is_a?(Arel::Nodes::Or) ? previous.children : [group(previous)]
        Arel::Nodes::Or.new([group(node), *children])
      end

      # A cannot rule only excludes the records that match its conditions: NULL does not match.
      def not_true(node)
        Arel::Nodes::InfixOperation.new('IS NOT', group(node), Arel.sql('TRUE'))
      end

      def group(node)
        Arel::Nodes::Grouping.new(node)
      end

      def single_can_rule?
        @compressed_rules.size == 1 && @compressed_rules.first.base_behavior && !@compressed_rules.first.with_scope?
      end

      def single_rule_conditions
        ConditionsExtractor.new(@model_class, joins).tableize_conditions(@compressed_rules.first.conditions).dup
      end

      def strategy_class
        strategy = CanCan.accessible_by_strategy
        return strategy if strategy.is_a?(Class)

        CanCan::ModelAdapters::Strategies.const_get(strategy.to_s.camelize)
      end

      # Removes empty hashes and moves everything into arrays.
      def deep_clean(joins_hash)
        joins_hash.map { |name, nested| nested.empty? ? name : { name => deep_clean(nested) } }
      end

      # Takes two hashes and does a deep merge.
      def deep_merge(base_hash, added_hash)
        added_hash.each do |key, value|
          if base_hash[key].is_a?(Hash)
            deep_merge(base_hash[key], value) unless value.empty?
          else
            base_hash[key] = value
          end
        end
      end

      def predicates(conditions, conditions_extractor)
        conditions.flat_map do |key, value|
          table_class = value.is_a?(Hash) && conditions_extractor&.model_class_for(key)
          if table_class
            predicate_builder(table_class, table_class.arel_table.alias(key.to_s)).build_from_hash(value.stringify_keys)
          else
            predicate_builder(@model_class, @model_class.arel_table).build_from_hash(key.to_s => value)
          end
        end
      end

      def predicate_builder(model_class, table)
        ActiveRecord::PredicateBuilder.new(ActiveRecord::TableMetadata.new(model_class, table))
      end

      def to_sql(node)
        connection = @model_class.lease_connection
        collector = Arel::Collectors::SubstituteBinds.new(connection, Arel::Collectors::SQLString.new)
        connection.visitor.accept(node, collector).value
      end
    end
  end
end

ActiveSupport.on_load(:active_record) do
  include CanCan::ModelAdditions
end
