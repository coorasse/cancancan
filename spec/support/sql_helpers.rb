# frozen_string_literal: true

module SQLHelpers
  def normalized_sql(adapter)
    adapter.database_records.to_sql.strip.squeeze(' ')
  end

  def sqlite?
    ENV['DB'] == 'sqlite'
  end

  def postgres?
    ENV['DB'] == 'postgres'
  end

  def count_queries(&)
    count = 0
    counter = lambda { |_name, _started, _finished, _unique_id, payload|
      count += 1 unless payload[:name].in? %w[CACHE SCHEMA]
    }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &)
    count
  end

  def connect_db
    # ActiveRecord::Base.logger = Logger.new(STDOUT)
    ActiveRecord::Base.logger = nil
    if sqlite?
      connect_sqlite
    elsif postgres?
      connect_postgres
    else
      raise StandardError, "database not supported: #{ENV['DB'].inspect}. Try DB='sqlite' or DB='postgres'"
    end
    drop_all_tables
  end

  private

  def connect_sqlite
    ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
  end

  # The same in-memory SQLite database can survive establish_connection, so start every example from a blank schema.
  def drop_all_tables
    connection = ActiveRecord::Base.connection
    connection.disable_referential_integrity do
      connection.tables.each { |table| connection.drop_table(table, force: :cascade) }
    end
  end

  def connect_postgres
    ActiveRecord::Base.establish_connection(adapter: 'postgresql', host: 'localhost',
                                            database: 'postgres', schema_search_path: 'public',
                                            user: 'postgres', password: 'postgres')
    ActiveRecord::Base.connection.drop_database('cancan_postgresql_spec')
    ActiveRecord::Base.connection.create_database('cancan_postgresql_spec', 'encoding' => 'utf-8',
                                                                            'adapter' => 'postgresql')
    ActiveRecord::Base.establish_connection(adapter: 'postgresql', host: 'localhost',
                                            database: 'cancan_postgresql_spec',
                                            user: 'postgres', password: 'postgres')
  end
end
