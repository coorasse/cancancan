module CanCan
  module ModelAdapters
    class Strategies
      class Base
        attr_reader :adapter, :relation, :where_conditions

        delegate(
          :compressed_rules,
          :joins,
          :model_class,
          :primary_key_in,
          :rule_conditions,
          to: :adapter
        )
        delegate :connection, :quoted_primary_key, to: :model_class
        delegate :quote_column_name, :quote_table_name, to: :connection

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

        # The join of the table with itself under an alias, matching the records on their primary key.
        def aliased_table_join
          "JOIN #{quoted_table_name} AS #{quoted_aliased_table_name} ON " \
            "#{matching_primary_keys(quoted_aliased_table_name, quoted_table_name)}"
        end

        # The condition that matches the same record in two tables, on every column of the primary key.
        def matching_primary_keys(left_table, right_table)
          Array(model_class.primary_key).map do |column|
            quoted_column = quote_column_name(column)
            "#{left_table}.#{quoted_column} = #{right_table}.#{quoted_column}"
          end.join(' AND ')
        end
      end
    end
  end
end
