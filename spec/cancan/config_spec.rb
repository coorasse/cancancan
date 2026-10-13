# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CanCan do
  describe '.accessible_by_strategy=' do
    it 'applies to every thread' do
      CanCan.accessible_by_strategy = :left_join

      expect(Thread.new { CanCan.accessible_by_strategy }.value).to eq(:left_join)
    end

    it 'applies to every fiber' do
      CanCan.accessible_by_strategy = :left_join

      expect(Fiber.new { CanCan.accessible_by_strategy }.resume).to eq(:left_join)
    end

    it 'rejects unknown strategies' do
      expect { CanCan.accessible_by_strategy = :unknown }.to raise_error(ArgumentError)
    end

    it 'accepts every built-in strategy' do
      CanCan.valid_accessible_by_strategies.each do |strategy|
        CanCan.accessible_by_strategy = strategy

        expect(CanCan.accessible_by_strategy).to eq(strategy)
      end
    end

    it 'accepts a subclass of CanCan::ModelAdapters::Strategies::Base' do
      strategy = Class.new(CanCan::ModelAdapters::Strategies::Base)

      CanCan.accessible_by_strategy = strategy

      expect(CanCan.accessible_by_strategy).to eq(strategy)
    end

    it 'rejects a class that is not a strategy' do
      expect { CanCan.accessible_by_strategy = String }
        .to raise_error(ArgumentError, /or a subclass of CanCan::ModelAdapters::Strategies::Base/)
    end

    it 'rejects a string' do
      expect { CanCan.accessible_by_strategy = 'left_join' }.to raise_error(ArgumentError)
    end
  end

  describe '.with_accessible_by_strategy' do
    before { CanCan.accessible_by_strategy = :subquery }

    it 'overrides the strategy inside the block and restores it afterwards' do
      strategy_in_block = CanCan.with_accessible_by_strategy(:left_join) { CanCan.accessible_by_strategy }

      expect(strategy_in_block).to eq(:left_join)
      expect(CanCan.accessible_by_strategy).to eq(:subquery)
    end

    it 'restores the strategy when the block raises' do
      expect do
        CanCan.with_accessible_by_strategy(:left_join) { raise 'boom' }
      end.to raise_error('boom')

      expect(CanCan.accessible_by_strategy).to eq(:subquery)
    end

    it 'supports nested blocks' do
      CanCan.with_accessible_by_strategy(:left_join) do
        CanCan.with_accessible_by_strategy(:subquery) do
          expect(CanCan.accessible_by_strategy).to eq(:subquery)
        end
        expect(CanCan.accessible_by_strategy).to eq(:left_join)
      end

      expect(CanCan.accessible_by_strategy).to eq(:subquery)
    end

    it 'rejects unknown strategies' do
      expect { CanCan.with_accessible_by_strategy(:unknown) { nil } }.to raise_error(ArgumentError)
    end

    it 'accepts a subclass of CanCan::ModelAdapters::Strategies::Base' do
      strategy = Class.new(CanCan::ModelAdapters::Strategies::Base)

      strategy_in_block = CanCan.with_accessible_by_strategy(strategy) { CanCan.accessible_by_strategy }

      expect(strategy_in_block).to eq(strategy)
      expect(CanCan.accessible_by_strategy).to eq(:subquery)
    end

    it 'does not leak the override into other threads' do
      inside_block = Queue.new
      other_thread_done = Queue.new

      other_thread = Thread.new do
        inside_block.pop
        strategy = CanCan.accessible_by_strategy
        other_thread_done.push(:done)
        strategy
      end

      CanCan.with_accessible_by_strategy(:left_join) do
        inside_block.push(:go)
        other_thread_done.pop
      end

      expect(other_thread.value).to eq(:subquery)
    end

    it 'does not leak the override into other fibers' do
      strategy_in_other_fiber = CanCan.with_accessible_by_strategy(:left_join) do
        Fiber.new { CanCan.accessible_by_strategy }.resume
      end

      expect(strategy_in_other_fiber).to eq(:subquery)
    end
  end

  describe '.warn_on_cannot_rule_with_scope' do
    before do
      connect_db
      ActiveRecord::Migration.verbose = false
      ActiveRecord::Schema.define do
        create_table(:products) do |t|
          t.boolean :discontinued
        end
      end
      stub_const('Product', Class.new(ActiveRecord::Base))
      CanCan.warn_on_cannot_rules_with_scope = true
    end

    let(:ability) { Class.new { include CanCan::Ability }.new }

    def capture_stderr
      stderr = $stderr
      $stderr = StringIO.new
      yield
      $stderr.string
    ensure
      $stderr = stderr
    end

    it 'warns once for a cannot rule with a scope' do
      warnings = Array.new(2) do
        capture_stderr { ability.cannot :read, Product, Product.where(discontinued: true) }
      end
      expect(warnings.first)
        .to match(/the scope of the cannot rule at .*config_spec.rb:\d+ selects the records that cannot be read/)
      expect(warnings.last).to be_empty
    end

    it 'warns for each rule defined through a helper method' do
      ability_class = Class.new do
        include CanCan::Ability

        def initialize
          forbid(Product.where(discontinued: true))
          forbid(Product.where(discontinued: false))
        end

        def forbid(scope)
          cannot :read, Product, scope
        end
      end
      expect { ability_class.new }
        .to output(/discontinued" = (TRUE|1).*\n.*discontinued" = (FALSE|0)/).to_stderr
    end

    it 'does not warn for a can rule with a scope or a cannot rule with a hash' do
      expect do
        ability.can :read, Product, Product.where(discontinued: false)
        ability.cannot :read, Product, discontinued: true
      end.not_to output.to_stderr
    end

    it 'does not warn when disabled' do
      CanCan.warn_on_cannot_rules_with_scope = false
      expect { ability.cannot :read, Product, Product.where(discontinued: true) }.not_to output.to_stderr
    end
  end
end
