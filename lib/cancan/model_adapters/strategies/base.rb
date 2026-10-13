module CanCan
  module ModelAdapters
    class Strategies
      class Base
        attr_reader :adapter, :relation, :where_conditions

        delegate(
          :compressed_rules,
          :joins,
          :model_class,
          :rule_conditions,
          to: :adapter
        )
        delegate :connection, :quoted_primary_key, to: :model_class
        delegate :quote_table_name, to: :connection

        def initialize(adapter:, relation:, where_conditions:)
          @adapter = adapter
          @relation = relation
          @where_conditions = where_conditions
        end

        # The records of the model with the joins of the rules, ignoring the scope `accessible_by` was called on.
        def joined_records
          model_class.unscoped { model_class.left_joins(joins) }
        end

        def aliased_table_name
          @aliased_table_name ||= "#{model_class.table_name}_alias"
        end

        def quoted_aliased_table_name
          @quoted_aliased_table_name ||= quote_table_name(aliased_table_name)
        end

        def quoted_table_name
          @quoted_table_name ||= quote_table_name(model_class.table_name)
        end
      end
    end
  end
end
