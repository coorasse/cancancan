module CanCan
  module ModelAdapters
    class Strategies
      class Subquery < Base
        def execute!
          model_class.where(model_class.primary_key => joined_records.where(where_conditions))
        end
      end
    end
  end
end
