# frozen_string_literal: true

require 'rubygems'
require 'bundler/setup'

Bundler.require

require 'matchers'
require 'cancan/matchers'

I18n.enforce_available_locales = false

# Add support to load paths
$LOAD_PATH.unshift File.expand_path('support', __dir__)
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each { |f| require f }

RSpec.configure do |config|
  config.filter_run focus: true
  config.run_all_when_everything_filtered = true
  config.disable_monkey_patching = true
  config.mock_with :rspec
  config.order = 'random'

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.include SQLHelpers

  config.before :suite do
    CanCan.warn_on_cannot_rules_with_scope = false
  end

  config.after :each do
    CanCan.accessible_by_strategy = CanCan.default_accessible_by_strategy
    CanCan.rules_compressor_enabled = true
    CanCan.warn_on_cannot_rules_with_scope = false
  end
end

RSpec::Matchers.define :generate_sql do |expected|
  match do |actual|
    normalized_sql(actual) == expected.gsub(/\s+/, ' ').strip
  end
  failure_message do |actual|
    "Returned sql:\n#{normalized_sql(actual)}\ninstead of:\n#{expected.gsub(/\s+/, ' ').strip}"
  end
end
