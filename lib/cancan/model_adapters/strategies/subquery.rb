module CanCan
  module ModelAdapters
    class Strategies
      class Subquery < Base
        def execute!
          model_class.where(primary_key_in(joined_records.where(where_conditions)))
        end
      end
    end
  end
end
