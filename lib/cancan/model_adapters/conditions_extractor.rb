# frozen_string_literal: true

# this class is responsible of converting the hash of conditions
# in "where conditions" to generate the sql query.
# Every association is given the table alias that ActiveRecord gives it when joining the associations,
# so it walks the joins in the same order and registers every joined table, through tables included.
module CanCan
  module ModelAdapters
    class ConditionsExtractor
      # Pass the associations given to `joins` and then to `left_joins`, as they are joined by ActiveRecord.
      def initialize(model_class, *joins)
        @root_model_class = model_class
        @aliases = Hash.new(0)
        @aliases[model_class.table_name] = 1
        @table_aliases = {}
        @joined_tables = {}
        @model_classes = {}
        joins.each { |associations| register_joins(model_class, joins_tree(associations), []) }
      end

      def tableize_conditions(conditions, model_class = @root_model_class, path = [])
        return conditions unless conditions.is_a? Hash

        conditions.each_with_object({}) do |(key, value), result_hash|
          if value.is_a? Hash
            tableize_association(model_class, path + [key.to_sym], value, result_hash)
          else
            result_hash[key] = value
          end
        end
      end

      # The model class of a table alias returned by tableize_conditions.
      def model_class_for(table_alias)
        @model_classes[table_alias.to_s]
      end

      private

      def tableize_association(model_class, path, conditions, result_hash)
        reflection = model_class.reflect_on_association(path.last)
        table_alias = @table_aliases[path] || register_association(model_class, reflection, path)
        nested, values = conditions.partition { |_key, value| value.is_a? Hash }.map(&:to_h)
        result_hash[table_alias.to_sym] = values unless values.empty?
        result_hash.merge!(tableize_conditions(nested, reflection.klass, path))
      end

      def joins_tree(joins)
        case joins
        when Hash then joins.to_h { |name, nested| [name.to_sym, joins_tree(nested)] }
        when Array then joins.each_with_object({}) { |nested, tree| tree.deep_merge!(joins_tree(nested)) }
        when nil then {}
        else { joins.to_sym => {} }
        end
      end

      # Mirrors ActiveRecord::Associations::JoinDependency#walk: the associations already joined come first.
      def register_joins(model_class, tree, path)
        joined, missing = tree.partition { |name, _nested| @table_aliases.key?(path + [name]) }
        (joined + missing).each do |name, nested|
          reflection = model_class.reflect_on_association(name)
          next if reflection.nil? || reflection.polymorphic?

          register_association(model_class, reflection, path + [name]) unless @table_aliases.key?(path + [name])
          register_joins(reflection.klass, nested, path + [name])
        end
      end

      def register_association(parent_class, reflection, path)
        chain = reflection.chain
        table_alias = nil
        chain.each_index do |index|
          table, reused = join_table(parent_class, chain, index)
          table_alias ||= table
          break if reused
        end
        @model_classes[table_alias] = reflection.klass
        @table_aliases[path] = table_alias
      end

      # Mirrors ActiveRecord::Associations::JoinDependency#make_constraints
      def join_table(parent_class, chain, index)
        root = index.zero?
        remaining_chain = chain[index..]
        table, terminated = @joined_tables[remaining_chain]
        return reuse_joined_table(remaining_chain, table, root) if reuse_joined_table?(table, root, terminated)

        table = aliased_table_for(chain[index].klass.table_name) do
          name = chain[index].alias_candidate(parent_class.table_name)
          root ? name : "#{name}_join"
        end
        @joined_tables[remaining_chain] ||= [table, root]
        [table, false]
      end

      def reuse_joined_table(remaining_chain, table, root)
        @joined_tables[remaining_chain] = [table, root] if root
        [table, true]
      end

      def reuse_joined_table?(table, root, terminated)
        table && (!root || !terminated)
      end

      # Mirrors ActiveRecord::Associations::AliasTracker#aliased_table_for
      def aliased_table_for(table_name)
        if @aliases[table_name].zero?
          @aliases[table_name] = 1
          return table_name
        end

        aliased_name = yield[0...table_alias_length].tr('.', '_')
        count = @aliases[aliased_name] += 1
        count > 1 ? "#{aliased_name[0, table_alias_length - 2]}_#{count}" : aliased_name
      end

      def table_alias_length
        @table_alias_length ||= @root_model_class.lease_connection.table_alias_length
      end
    end
  end
end
