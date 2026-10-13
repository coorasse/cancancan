# frozen_string_literal: true

module CanCan
  module ModelAdapters
    class Strategies
      class JoinedAliasExistsSubquery < Base
        def execute!
          model_class
            .joins(aliased_table_join)
            .where("EXISTS (#{joined_alias_exists_subquery_inner_query.to_sql})")
        end

        def joined_alias_exists_subquery_inner_query
          joined_records
            .select('1')
            .where(where_conditions)
            .where(matching_primary_keys(quoted_table_name, quoted_aliased_table_name))
            .limit(1)
        end
      end
    end
  end
end
