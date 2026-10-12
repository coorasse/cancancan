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

        def parent_condition_name(parent, child)
          child_association_to_parent(parent, child)&.name || parent.class.name.downcase.to_sym
        end
      end

      # Returns conditions intended to be used inside a database query. Normally you will not call this
      # method directly, but instead go through ModelAdditions#accessible_by.
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
      #   query(:manage, User).conditions # => "not (self_managed = 't') AND ((manager_id = 1) OR (id = 1))"
      #
      def conditions
        extract_conditions(ConditionsExtractor.new(@model_class, joins))
      end

      def extract_multiple_conditions(conditions_extractor, rules)
        sql, = rules.reverse.inject([false_sql, false]) do |(sql, or_chain), rule|
          conditions_hash = conditions_extractor.tableize_conditions(rule.conditions).dup
          merge_conditions(sql, or_chain, conditions_hash, rule.base_behavior, conditions_extractor)
        end
        sql
      end

      def database_records
        if override_scope
          merge_override_scope
        else
          build_relation(where_conditions)
        end
      end

      def build_relation(*where_conditions)
        relation = @model_class.where(*where_conditions)
        return relation unless joins.present?

        strategy_class.new(adapter: self, relation: relation, where_conditions: where_conditions).execute!
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

      private

      def strategy_class
        strategy = CanCan.accessible_by_strategy
        return strategy if strategy.is_a?(Class)

        CanCan::ModelAdapters::Strategies.const_get(strategy.to_s.camelize)
      end

      def extract_conditions(conditions_extractor)
        if @compressed_rules.size == 1 && @compressed_rules.first.base_behavior
          # Return the conditions directly if there's just one definition
          conditions_extractor.tableize_conditions(@compressed_rules.first.conditions).dup
        else
          extract_multiple_conditions(conditions_extractor, @compressed_rules)
        end
      end

      # Active Record cannot find the model of an aliased table in a hash of conditions,
      # so the conditions on associations are converted to SQL with the model of each table.
      def where_conditions
        conditions_extractor = ConditionsExtractor.new(@model_class, joins)
        conditions = extract_conditions(conditions_extractor)
        return conditions unless conditions.is_a?(Hash) && conditions.values.any? { |value| value.is_a?(Hash) }

        where_node(conditions, conditions_extractor)
      end

      def where_node(conditions, conditions_extractor)
        Arel::Nodes::And.new(predicates(conditions, conditions_extractor))
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

      # `merge` replaces the conditions of the base relation on the columns the scope also constrains,
      # so the conditions it dropped, like the one of an association like `category.articles`, are applied again.
      # The conditions the scope removes with `unscope`, like the ones of a default scope, stay removed.
      def merge_override_scope
        merged = @model_class.where(nil).merge(override_scope)
        base = @model_class.where(nil)
        base = base.unscope(*override_scope.unscope_values) if override_scope.unscope_values.any?
        dropped = base.where_clause.send(:predicates) - merged.where_clause.send(:predicates)
        dropped.inject(merged) { |relation, predicate| relation.where(predicate) }
      end

      def override_scope
        conditions = @compressed_rules.map(&:conditions).compact
        return unless conditions.any?(ActiveRecord::Relation)
        return conditions.first if conditions.size == 1

        raise_override_scope_error
      end

      def raise_override_scope_error
        rule_found = @compressed_rules.detect { |rule| rule.conditions.is_a?(ActiveRecord::Relation) }
        raise Error,
              'Unable to merge an Active Record scope with other conditions. ' \
              "Instead use a hash or SQL for #{rule_found.actions.first} #{rule_found.subjects.first} ability."
      end

      # Returns the merged sql and whether it is a flat chain of OR conditions.
      def merge_conditions(sql, or_chain, conditions_hash, behavior, conditions_extractor)
        if conditions_hash.blank?
          [behavior ? true_sql : false_sql, false]
        else
          merge_non_empty_conditions(behavior, sanitize_sql(conditions_hash, conditions_extractor), sql, or_chain)
        end
      end

      # Consecutive `can` rules are joined in a flat chain of ORs, so that the nesting of the query only grows
      # when `can` and `cannot` rules alternate. Deeply nested conditions overflow the parser of SQLite.
      def merge_non_empty_conditions(behavior, conditions, sql, or_chain)
        case sql
        when true_sql
          behavior ? [true_sql, false] : [not_conditions(conditions), false]
        when false_sql
          behavior ? [conditions, false] : [false_sql, false]
        else
          merge_with_previous_conditions(behavior, conditions, sql, or_chain)
        end
      end

      def merge_with_previous_conditions(behavior, conditions, sql, or_chain)
        if behavior
          [or_conditions(conditions, sql, or_chain), true]
        else
          ["#{not_conditions(conditions)} AND (#{sql})", false]
        end
      end

      # A cannot rule only excludes the records that match its conditions: NULL does not match.
      def not_conditions(conditions)
        "(#{conditions}) IS NOT TRUE"
      end

      def or_conditions(conditions, sql, or_chain)
        "(#{conditions}) OR #{or_chain ? sql : "(#{sql})"}"
      end

      def false_sql
        sanitize_sql(['?=?', true, false])
      end

      def true_sql
        sanitize_sql(['?=?', true, true])
      end

      def sanitize_sql(conditions, conditions_extractor = nil)
        return @model_class.send(:sanitize_sql, conditions) unless conditions.is_a?(Hash)

        predicates(conditions, conditions_extractor).map { |node| visit_node(node) }.join(' AND ')
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

      def visit_node(node)
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
