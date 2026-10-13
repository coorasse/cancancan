# frozen_string_literal: true

require 'spec_helper'

describe CanCan::Ability do
  before(:each) do
    (@ability = double).extend(CanCan::Ability)

    connect_db
    ActiveRecord::Migration.verbose = false
    ActiveRecord::Schema.define do
      create_table(:named_users) do |t|
        t.string :first_name
        t.string :last_name
      end
    end

    unless defined?(NamedUser)
      class NamedUser < ActiveRecord::Base
        attribute :role, :string # Virtual only
      end
    end
  end

  it 'is able to :read anything' do
    @ability.can :read, :all
    expect(@ability.can?(:read, String)).to be(true)
    expect(@ability.can?(:read, 123)).to be(true)
  end

  it "does not have permission to do something it doesn't know about" do
    expect(@ability.can?(:foodfight, String)).to be(false)
  end

  it 'passes true to `can?` when non false/nil is returned in block' do
    @ability.can :read, Symbol do |sym|
      expect(sym).not_to be_nil
      'foo'
    end
    expect(@ability.can?(:read, :some_symbol)).to be(true)
  end

  it 'passes nil to a block when no instance is passed' do
    @ability.can :read, Symbol do |sym|
      expect(sym).to be_nil
      true
    end
    expect(@ability.can?(:read, Symbol)).to be(true)
  end

  it 'passes to previous rule, if block returns false or nil' do
    @ability.can :read, Symbol
    @ability.can :read, Integer do |i|
      i < 5
    end
    @ability.can :read, Integer do |i|
      i > 10
    end
    expect(@ability.can?(:read, Symbol)).to be(true)
    expect(@ability.can?(:read, 11)).to be(true)
    expect(@ability.can?(:read, 1)).to be(true)
    expect(@ability.can?(:read, 6)).to be(false)
  end

  it 'overrides earlier rules with later ones (even if a different exact subject)' do
    @ability.cannot :read, Numeric
    @ability.can :read, Integer

    expect(@ability.can?(:read, 6)).to be(true)
  end

  it 'performs can(_, :all) before other checks when can(_, :all) is defined before' do
    @ability.can :manage, :all
    @ability.can :edit, String do |_string|
      raise 'Performed a check for :edit before the check for :all'
    end
    expect { @ability.can? :edit, 'a' }.to_not raise_exception
  end

  it 'performs can(_, :all) before other checks when can(_, :all) is defined after' do
    @ability.can :edit, String do |_string|
      raise 'Performed a check for :edit before the check for :all'
    end
    @ability.can :manage, :all
    expect { @ability.can? :edit, 'a' }.to_not raise_exception
  end

  it 'does not pass class with object if :all objects are accepted' do
    @ability.can :preview, :all do |object|
      expect(object).to eq(123)
      @block_called = true
    end
    @ability.can?(:preview, 123)
    expect(@block_called).to be(true)
  end

  it 'does not call block when only class is passed, only return true' do
    @block_called = false
    @ability.can :preview, :all do |_object|
      @block_called = true
    end
    expect(@ability.can?(:preview, Hash)).to be(true)
    expect(@block_called).to be(false)
  end

  it 'passes only object for global manage actions' do
    @ability.can :manage, String do |object|
      expect(object).to eq('foo')
      @block_called = true
    end
    expect(@ability.can?(:stuff, 'foo')).to be(true)
    expect(@block_called).to be(true)
  end

  it 'makes alias for update or destroy actions to modify action' do
    @ability.alias_action :update, :destroy, to: :modify
    @ability.can :modify, :all
    expect(@ability.can?(:update, 123)).to be(true)
    expect(@ability.can?(:destroy, 123)).to be(true)
  end

  it 'allows deeply nested aliased actions' do
    @ability.alias_action :increment, to: :sort
    @ability.alias_action :sort, to: :modify
    @ability.can :modify, :all
    expect(@ability.can?(:increment, 123)).to be(true)
  end

  it 'raises an Error if alias target is an exist action' do
    expect { @ability.alias_action :show, to: :show }
      .to raise_error(CanCan::Error, "You can't specify target (show) as alias because it is real action name")
  end

  it 'raises an Error if alias target is :manage' do
    expect { @ability.alias_action :read, to: :manage }
      .to raise_error(CanCan::Error, "You can't specify target (manage) as alias because it is a reserved action")
  end

  it 'raises an Error if an action is aliased to itself' do
    expect { @ability.alias_action :approve, to: :approve }
      .to raise_error(CanCan::Error, "You can't alias the action (approve) to itself")
  end

  it 'always calls block with arguments when passing no arguments to can' do
    @ability.can do |action, object_class, object|
      expect(action).to eq(:foo)
      expect(object_class).to eq(123.class)
      expect(object).to eq(123)
      @block_called = true
    end
    @ability.can?(:foo, 123)
    expect(@block_called).to be(true)
  end

  it 'allows passing nil as extra arguments' do
    @ability.can :to_s, Integer do |integer, arg1, arg2|
      expect(integer).to eq(42)
      expect(arg1).to eq(nil)
      expect(arg2).to eq(:foo)
      @block_called = true
    end
    @ability.can?(:to_s, 42, nil, nil, :foo)
    expect(@block_called).to be(true)
  end

  it 'passes nil to object when comparing class with can check' do
    @ability.can do |action, object_class, object|
      expect(action).to eq(:foo)
      expect(object_class).to eq(Hash)
      expect(object).to be_nil
      @block_called = true
    end
    @ability.can?(:foo, Hash)
    expect(@block_called).to be(true)
  end

  it 'automatically makes alias for index and show into read calls' do
    @ability.can :read, :all
    expect(@ability.can?(:index, 123)).to be(true)
    expect(@ability.can?(:show, 123)).to be(true)
  end

  it 'automatically makes alias for new and edit into create and update respectively' do
    @ability.can :create, :all
    @ability.can :update, :all
    expect(@ability.can?(:new, 123)).to be(true)
    expect(@ability.can?(:edit, 123)).to be(true)
  end

  it 'does not respond to prepare (now using initialize)' do
    expect(@ability).to_not respond_to(:prepare)
  end

  it 'offers cannot? method which is simply invert of can?' do
    expect(@ability.cannot?(:tie, String)).to be(true)
  end

  it 'is able to specify multiple actions and match any' do
    @ability.can %i[read update], :all
    expect(@ability.can?(:read, 123)).to be(true)
    expect(@ability.can?(:update, 123)).to be(true)
    expect(@ability.can?(:count, 123)).to be(false)
  end

  it 'is able to specify multiple classes and match any' do
    @ability.can :update, [String, Range]
    expect(@ability.can?(:update, 'foo')).to be(true)
    expect(@ability.can?(:update, 1..3)).to be(true)
    expect(@ability.can?(:update, 123)).to be(false)
  end

  it 'checks if there is a permission for any of given subjects' do
    @ability.can :update, [String, Range]
    expect(@ability.can?(:update, any: ['foo', 1..3])).to be(true)
    expect(@ability.can?(:update, any: [1..3, 'foo'])).to be(true)
    expect(@ability.can?(:update, any: [123, 'foo'])).to be(true)
    expect(@ability.can?(:update, any: [123, 1.0])).to be(false)
  end

  it 'lists all permissions' do
    @ability.can :manage, :all
    @ability.can :learn, Range
    @ability.can :interpret, Symbol, %i[size to_s]
    @ability.cannot :read, String
    @ability.cannot :read, Hash
    @ability.cannot :preview, Array

    expected_list = {
      can: {
        manage: { 'all' => [] },
        learn: { 'Range' => [] },
        interpret: { 'Symbol' => %i[size to_s] }
      },
      cannot: {
        read: { 'String' => [], 'Hash' => [] },
        index: { 'String' => [], 'Hash' => [] },
        show: { 'String' => [], 'Hash' => [] },
        preview: { 'Array' => [] }
      }
    }

    expect(@ability.permissions).to eq(expected_list)
  end

  it 'supports custom objects in the rule' do
    @ability.can :read, :stats
    expect(@ability.can?(:read, :stats)).to be(true)
    expect(@ability.can?(:update, :stats)).to be(false)
    expect(@ability.can?(:read, :nonstats)).to be(false)
    expect(@ability.can?(:read, any: %i[stats nonstats])).to be(true)
    expect(@ability.can?(:read, any: %i[nonstats neitherstats])).to be(false)
  end

  it 'checks ancestors of class' do
    @ability.can :read, Numeric
    expect(@ability.can?(:read, Integer)).to be(true)
    expect(@ability.can?(:read, 1.23)).to be(true)
    expect(@ability.can?(:read, 'foo')).to be(false)
    expect(@ability.can?(:read, any: [Integer, String])).to be(true)
  end

  it "supports 'cannot' method to define what user cannot do" do
    @ability.can :read, :all
    @ability.cannot :read, Integer
    expect(@ability.can?(:read, 'foo')).to be(true)
    expect(@ability.can?(:read, 123)).to be(false)
    expect(@ability.can?(:read, any: %w[foo bar])).to be(true)
    expect(@ability.can?(:read, any: [123, 'foo'])).to be(false)
    expect(@ability.can?(:read, any: [123, 456])).to be(false)
  end

  it 'passes to previous rule, if block returns false or nil' do
    @ability.can :read, :all
    @ability.cannot :read, Integer do |int|
      int > 10 ? nil : (int > 5)
    end

    expect(@ability.can?(:read, 'foo')).to be(true)
    expect(@ability.can?(:read, 3)).to be(true)
    expect(@ability.can?(:read, 8)).to be(false)
    expect(@ability.can?(:read, 123)).to be(true)
    expect(@ability.can?(:read, any: [123, 8])).to be(true)
    expect(@ability.can?(:read, any: [8, 9])).to be(false)
  end

  it 'always returns `false` for single cannot definition' do
    @ability.cannot :read, Integer do |int|
      int > 10 ? nil : (int > 5)
    end
    expect(@ability.can?(:read, 'foo')).to be(false)
    expect(@ability.can?(:read, 3)).to be(false)
    expect(@ability.can?(:read, 8)).to be(false)
    expect(@ability.can?(:read, 123)).to be(false)
  end

  it 'passes to previous cannot definition, if block returns false or nil' do
    @ability.cannot :read, :all
    @ability.can :read, Integer do |int|
      int > 10 ? nil : (int > 5)
    end
    expect(@ability.can?(:read, 'foo')).to be(false)
    expect(@ability.can?(:read, 3)).to be(false)
    expect(@ability.can?(:read, 10)).to be(true)
    expect(@ability.can?(:read, 123)).to be(false)
  end

  it 'appends aliased actions' do
    @ability.alias_action :update, to: :modify
    @ability.alias_action :destroy, to: :modify
    expect(@ability.aliased_actions[:modify]).to eq(%i[update destroy])
  end

  it 'clears aliased actions' do
    @ability.alias_action :update, to: :modify
    @ability.clear_aliased_actions
    expect(@ability.aliased_actions[:modify]).to be_nil
  end

  it 'does not expand cleared aliased actions after a check' do
    @ability.can :read, Integer
    expect(@ability.can?(:index, Integer)).to be(true)
    @ability.clear_aliased_actions
    expect(@ability.can?(:index, Integer)).to be(false)
  end

  it 'expands aliased actions added after a check' do
    @ability.can :modify, Integer
    expect(@ability.can?(:update, Integer)).to be(false)
    @ability.alias_action :update, to: :modify
    expect(@ability.can?(:update, Integer)).to be(true)
  end

  it 'applies an alias defined after a check' do
    @ability.can :modify, :all
    expect(@ability.can?(:update, 123)).to be(false)
    @ability.alias_action :update, to: :modify
    expect(@ability.can?(:update, 123)).to be(true)
  end

  it 'forgets the default aliases cleared after a check' do
    @ability.can :read, :all
    expect(@ability.can?(:index, 123)).to be(true)
    @ability.clear_aliased_actions
    expect(@ability.can?(:index, 123)).to be(false)
  end

  it 'passes additional arguments to block from can?' do
    @ability.can :read, Integer do |int, x|
      int > x
    end

    expect(@ability.can?(:read, 2, 1)).to be(true)
    expect(@ability.can?(:read, 2, 3)).to be(false)
    expect(@ability.can?(:read, { any: [4, 5] }, 3)).to be(true)
    expect(@ability.can?(:read, { any: [2, 3] }, 3)).to be(false)
  end

  it 'uses conditions as third parameter and determine abilities from it' do
    @ability.can :read, Range, begin: 1, end: 3

    expect(@ability.can?(:read, 1..3)).to be(true)
    expect(@ability.can?(:read, 1..4)).to be(false)
    expect(@ability.can?(:read, Range)).to be(true)
    expect(@ability.can?(:read, any: [1..3, 1..4])).to be(true)
    expect(@ability.can?(:read, any: [1..4, 2..4])).to be(false)
  end

  it 'allows an array of options in conditions hash' do
    @ability.can :read, Range, begin: [1, 3, 5]

    expect(@ability.can?(:read, 1..3)).to be(true)
    expect(@ability.can?(:read, 2..4)).to be(false)
    expect(@ability.can?(:read, 3..5)).to be(true)
    expect(@ability.can?(:read, any: [2..4, 3..5])).to be(true)
    expect(@ability.can?(:read, any: [2..4, 2..5])).to be(false)
  end

  it 'allows a range of options in conditions hash' do
    @ability.can :read, Range, begin: 1..3
    expect(@ability.can?(:read, 1..10)).to be(true)
    expect(@ability.can?(:read, 3..30)).to be(true)
    expect(@ability.can?(:read, 4..40)).to be(false)
  end

  it 'allows an array of ranges and values in conditions hash' do
    @ability.can :read, Range, begin: [1..3, 10..20, 7]
    expect(@ability.can?(:read, 2..10)).to be(true)
    expect(@ability.can?(:read, 15..30)).to be(true)
    expect(@ability.can?(:read, 7..8)).to be(true)
    expect(@ability.can?(:read, 5..6)).to be(false)
  end

  it 'allows a range of time in conditions hash' do
    @ability.can :read, Range, begin: 1.day.from_now..3.days.from_now
    expect(@ability.can?(:read, 1.day.from_now..10.days.from_now)).to be(true)
    expect(@ability.can?(:read, 2.days.from_now..20.days.from_now)).to be(true)
    expect(@ability.can?(:read, 4.days.from_now..40.days.from_now)).to be(false)
  end

  it 'allows nested hashes in conditions hash' do
    @ability.can :read, Range, begin: { to_i: 5 }
    expect(@ability.can?(:read, 5..7)).to be(true)
    expect(@ability.can?(:read, 6..8)).to be(false)
  end

  it "matches any element passed in to nesting if it's an array (for has_many associations)" do
    @ability.can :read, Range, to_a: { to_i: 3 }
    expect(@ability.can?(:read, 1..5)).to be(true)
    expect(@ability.can?(:read, 4..6)).to be(false)
  end

  it 'accepts a set as a condition value' do
    expect(object_with_foo_two = double(foo: 2)).to receive(:foo)
    expect(object_with_foo_three = double(foo: 3)).to receive(:foo)
    @ability.can :read, Object, foo: [1, 2, 5].to_set
    expect(@ability.can?(:read, object_with_foo_two)).to be(true)
    expect(@ability.can?(:read, object_with_foo_three)).to be(false)
  end

  it 'does not match subjects return nil for methods that must match nested a nested conditions hash' do
    expect(object_with_foo = double(foo: :bar)).to receive(:foo)
    @ability.can :read, Array, first: { foo: :bar }
    expect(@ability.can?(:read, [object_with_foo])).to be(true)
    expect(@ability.can?(:read, [])).to be(false)
  end

  it 'matches strings but not substrings specified in a conditions hash' do
    @ability.can :read, String, presence: 'declassified'
    expect(@ability.can?(:read, 'declassified')).to be(true)
    expect(@ability.can?(:read, 'classified')).to be(false)
  end

  it 'does not stop at cannot definition when comparing class' do
    @ability.can :read, Range
    @ability.cannot :read, Range, begin: 1
    expect(@ability.can?(:read, 2..5)).to be(true)
    expect(@ability.can?(:read, 1..5)).to be(false)
    expect(@ability.can?(:read, Range)).to be(true)
  end

  it 'does not stop at cannot with block when comparing class' do
    @ability.can :read, Integer
    @ability.cannot(:read, Integer) { |int| int > 5 }
    expect(@ability.can?(:read, 123)).to be(false)
    expect(@ability.can?(:read, Integer)).to be(true)
  end

  it 'stops at cannot definition when no hash is present' do
    @ability.can :read, :all
    @ability.cannot :read, Range
    expect(@ability.can?(:read, 1..5)).to be(false)
    expect(@ability.can?(:read, Range)).to be(false)
  end

  it 'allows to check ability for Module' do
    module B
    end
    class A
      include B
    end
    @ability.can :read, B
    expect(@ability.can?(:read, A)).to be(true)
    expect(@ability.can?(:read, A.new)).to be(true)
  end

  it 'passes nil to a block for ability on Module when no instance is passed' do
    module B
    end
    class A
      include B
    end
    @ability.can :read, B do |sym|
      expect(sym).to be_nil
      true
    end
    expect(@ability.can?(:read, B)).to be(true)
    expect(@ability.can?(:read, A)).to be(true)
  end

  it 'checks permissions through association when passing a hash of subjects' do
    @ability.can :read, Range, string: { length: 3 }

    expect(@ability.can?(:read, 'foo' => Range)).to be(true)
    expect(@ability.can?(:read, 'foobar' => Range)).to be(false)
    expect(@ability.can?(:read, 123 => Range)).to be(true)
    expect(@ability.can?(:read, any: [{ 'foo' => Range }, { 'foobar' => Range }])).to be(true)
    expect(@ability.can?(:read, any: [{ 'food' => Range }, { 'foobar' => Range }])).to be(false)
  end

  it 'checks permissions correctly when passing a hash of subjects with multiple definitions' do
    @ability.can :read, Range, string: { length: 4 }
    @ability.can %i[create read], Range, string: { upcase: 'FOO' }

    expect(@ability.can?(:read, 'foo' => Range)).to be(true)
    expect(@ability.can?(:read, 'foobar' => Range)).to be(false)
    expect(@ability.can?(:read, 1234 => Range)).to be(true)
    expect(@ability.can?(:read, any: [{ 'foo' => Range }, { 'foobar' => Range }])).to be(true)
    expect(@ability.can?(:read, any: [{ 'foo.bar' => Range }, { 'foobar' => Range }])).to be(false)
  end

  it 'allows to check ability on Hash-like object' do
    class Container < Hash
    end
    @ability.can :read, Container
    expect(@ability.can?(:read, Container.new)).to be(true)
  end

  it "has initial values based on hash conditions of 'new' action" do
    @ability.can :manage, Range, foo: 'foo', hash: { skip: 'hashes' }
    @ability.can :create, Range, bar: 123, array: %w[skip arrays]
    @ability.can :new, Range, baz: 'baz', range: 1..3
    @ability.cannot :new, Range, ignore: 'me'
    expect(@ability.attributes_for(:new, Range)).to eq(foo: 'foo', bar: 123, baz: 'baz')
  end

  describe '#attributes_for' do
    it 'has no initial values when a rule without conditions allows the action' do
      @ability.can :create, Range
      @ability.can :create, Range, slow: true
      expect(@ability.attributes_for(:create, Range)).to eq({})
    end

    it 'has no initial values when a rule without conditions on :all allows the action' do
      @ability.can :manage, :all
      @ability.can :create, Range, slow: true
      expect(@ability.attributes_for(:create, Range)).to eq({})
    end

    it 'takes the value of the most recent rule' do
      @ability.can :new, Range, bar: 22
      @ability.can :new, Range, bar: 33
      expect(@ability.attributes_for(:new, Range)).to eq(bar: 33)
    end

    it 'ignores the rules defined before a cannot rule without conditions' do
      @ability.can :new, Range, bar: 22, foo: 'foo'
      @ability.cannot :new, Range
      @ability.can :new, Range, bar: 33
      expect(@ability.attributes_for(:new, Range)).to eq(bar: 33)
    end

    it 'keeps the rules defined before a cannot rule on attributes' do
      @ability.can :new, Range, bar: 22
      @ability.cannot :new, Range, :bar
      expect(@ability.attributes_for(:new, Range)).to eq(bar: 22)
    end

    it 'keeps the values of the rules defined before a rule with a block' do
      @ability.can :new, Range, bar: 22
      @ability.can(:new, Range) { |range| range.first.positive? }
      expect(@ability.attributes_for(:new, Range)).to eq(bar: 22)
    end
  end

  it 'allows to check ability even the object implements `#to_a`' do
    stub_const('X', Class.new do
      def self.to_a
        []
      end
    end)

    @ability.can :read, X
    expect(@ability.can?(:read, X.new)).to be(true)
  end

  it 'respects `#to_ary`' do
    stub_const('X', Class.new do
      def self.to_ary
        [Y]
      end
    end)

    stub_const('Y', Class.new)

    @ability.can :read, X
    expect(@ability.can?(:read, X.new)).to be(false)
    expect(@ability.can?(:read, Y.new)).to be(true)
  end

  # rubocop:disable-next Style/SymbolProc
  describe 'different usages of blocks and procs' do
    class A
      def active?
        true
      end
    end
    it 'can use a do...end block' do
      @ability.can :read, A do |a|
        a.active?
      end
      expect(@ability).to be_able_to(:read, A.new)
    end

    it 'can use a inline block' do
      @ability.can(:read, A) { |a| a.active? }
      expect(@ability).to be_able_to(:read, A.new)
    end

    it 'can use a method reference' do
      @ability.can :read, A, &:active?
      expect(@ability).to be_able_to(:read, A.new)
    end

    it 'can use a Proc' do
      proc = Proc.new(&:active?)
      @ability.can :read, A, &proc
      expect(@ability).to be_able_to(:read, A.new)
    end
  end

  describe '#authorize!' do
    describe 'when ability is not authorized to perform an action' do
      it 'raises access denied exception' do
        begin
          @ability.authorize! :read, :foo, 1, 2, 3, message: 'Access denied!'
        rescue CanCan::AccessDenied => e
          expect(e.message).to eq('Access denied!')
          expect(e.action).to eq(:read)
          expect(e.subject).to eq(:foo)
          expect(e.conditions).to eq([1, 2, 3])
        else
          raise 'Expected CanCan::AccessDenied exception to be raised'
        end
      end

      describe 'when no extra conditions are specified' do
        it 'raises access denied exception without conditions' do
          begin
            @ability.authorize! :read, :foo, message: 'Access denied!'
          rescue CanCan::AccessDenied => e
            expect(e.conditions).to eq([])
          else
            raise 'Expected CanCan::AccessDenied exception to be raised'
          end
        end
      end

      describe 'when no message is specified' do
        it 'raises access denied exception with default message' do
          begin
            @ability.authorize! :read, :foo
          rescue CanCan::AccessDenied => e
            e.default_message = 'Access denied!'
            expect(e.message).to eq('Access denied!')
          else
            raise 'Expected CanCan::AccessDenied exception to be raised'
          end
        end
      end
    end

    describe 'when ability is authorized to perform an action' do
      it 'does not raise access denied exception' do
        @ability.can :read, :foo
        expect do
          expect(@ability.authorize!(:read, :foo)).to eq(:foo)
        end.to_not raise_error
      end
    end
  end

  it 'knows when block is used in conditions' do
    @ability.can :read, :foo
    expect(@ability).to_not have_block(:read, :foo)
    @ability.can :read, :foo do |_foo|
      false
    end
    expect(@ability).to have_block(:read, :foo)
  end

  it 'knows when raw sql is used in conditions' do
    @ability.can :read, :foo
    expect(@ability).to_not have_raw_sql(:read, :foo)
    @ability.can :read, :foo, 'false'
    expect(@ability).to have_raw_sql(:read, :foo)
  end

  it 'determines model adapter class by asking AbstractAdapter' do
    adapter_class = double
    model_class = double
    allow(CanCan::ModelAdapters::AbstractAdapter).to receive(:adapter_class).with(model_class) { adapter_class }
    allow(adapter_class).to receive(:new).with(model_class, []) { :adapter_instance }
    expect(@ability.model_adapter(model_class, :read)).to eq(:adapter_instance)
  end

  it "raises an error when attempting to use a block with a hash condition since it's not likely what they want" do
    expect do
      @ability.can :read, Array, published: true do
        false
      end
    end.to raise_error(CanCan::BlockAndConditionsError)
  end

  it 'allows attribute-level rules' do
    @ability.can :read, Array, :to_s
    expect(@ability.can?(:read, Array, :to_s)).to be(true)
    expect(@ability.can?(:read, Array, :size)).to be(false)
    expect(@ability.can?(:read, Array)).to be(true)
  end

  it 'allows an array of attributes in rules' do
    @ability.can :read, [Array, String], %i[to_s size]
    expect(@ability.can?(:read, String, :size)).to be(true)
    expect(@ability.can?(:read, Array, :to_s)).to be(true)
  end

  it 'allows cannot of rules with attributes' do
    @ability.can :read, Array
    @ability.cannot :read, Array, :to_s
    expect(@ability.can?(:read, Array, :to_s)).to be(false)
    expect(@ability.can?(:read, Array)).to be(true)
    expect(@ability.can?(:read, Array, :size)).to be(true)
  end

  it 'has precedence with attribute-level rules' do
    @ability.cannot :read, Array
    @ability.can :read, Array, :to_s
    expect(@ability.can?(:read, Array, :to_s)).to be(true)
    expect(@ability.can?(:read, Array, :size)).to be(false)
    expect(@ability.can?(:read, Array)).to be(true)
  end

  it 'allows permission on all attributes when none are given' do
    @ability.can :update, Object
    expect(@ability.can?(:update, Object, :password)).to be(true)
  end

  it 'allows strings when checking attributes' do
    @ability.can :update, Object, :name
    expect(@ability.can?(:update, Object, 'name')).to be(true)
  end

  it 'allows strings when checking actions' do
    @ability.can :manage, :all
    @ability.cannot :destroy, Integer
    expect(@ability.can?('destroy', 123)).to be(false)
    expect(@ability.can?('read', 123)).to be(true)
  end

  it 'allows strings when defining actions and aliases' do
    @ability.alias_action 'publish', to: 'update'
    @ability.can :manage, :all
    @ability.cannot 'update', Integer
    expect(@ability.can?(:update, 123)).to be(false)
    expect(@ability.can?(:publish, 123)).to be(false)
  end

  it 'passes attribute to block; nil if no attribute given' do
    @ability.can :update, Range do |_range, attribute|
      attribute == :name
    end
    expect(@ability.can?(:update, 1..3, :name)).to be(true)
    expect(@ability.can?(:update, 2..4)).to be(false)
  end

  it 'combines attribute checks with conditions hash' do
    @ability.can :update, Range, begin: 1
    @ability.can :update, Range, :name, begin: 2
    expect(@ability.can?(:update, 1..3, :notname)).to be(true)
    expect(@ability.can?(:update, 2..4, :notname)).to be(false)
    expect(@ability.can?(:update, 2..4, :name)).to be(true)
    expect(@ability.can?(:update, 3..5, :name)).to be(false)
    expect(@ability.can?(:update, Range)).to be(true)
    expect(@ability.can?(:update, Range, :name)).to be(true)
  end

  it 'returns an array of permitted attributes for a given action and subject' do
    @ability.can :read, NamedUser
    @ability.can :read, Array, :special
    @ability.can :action, :subject, :attribute
    expect(@ability.permitted_attributes(:read, NamedUser)).to eq(%i[first_name last_name role])
    expect(@ability.permitted_attributes(:read, Array)).to eq([:special])
    expect(@ability.permitted_attributes(:action, :subject)).to eq([:attribute])
  end

  it 'returns permitted attributes when used with blocks' do
    user_class = Struct.new(:first_name, :last_name)
    @ability.can :read, user_class, %i[first_name last_name]
    @ability.cannot(:read, user_class, :first_name) { |u| u.last_name == 'Smith' }
    expect(@ability.permitted_attributes(:read, user_class.new('John', 'Jones'))).to eq(%i[first_name last_name])
    expect(@ability.permitted_attributes(:read, user_class.new('John', 'Smith'))).to eq(%i[last_name])
  end

  it 'returns permitted attributes when using conditions' do
    @ability.can :read, Range, %i[nil? to_s class]
    @ability.cannot :read, Range, %i[nil? to_s], begin: 2
    @ability.can :read, Range, :to_s, end: 4
    expect(@ability.permitted_attributes(:read, 1..3)).to eq(%i[nil? to_s class])
    expect(@ability.permitted_attributes(:read, 2..5)).to eq([:class])
    expect(@ability.permitted_attributes(:read, 2..4)).to eq(%i[class to_s])
  end

  it 'removes the attributes of a can rule when a cannot rule has no attributes' do
    @ability.can :update, Range, %i[first last]
    @ability.cannot :update, Range
    expect(@ability.permitted_attributes(:update, Range)).to eq([])
  end

  it 'returns permitted attributes for a hash subject' do
    @ability.can :read, NamedUser
    expect(@ability.permitted_attributes(:read, Array => NamedUser)).to eq(%i[first_name last_name role])
  end

  it 'respects inheritance when checking permitted attributes' do
    @ability.can :read, Integer, %i[nil? to_s class]
    @ability.cannot :read, Numeric, %i[nil? class]
    expect(@ability.permitted_attributes(:read, Integer)).to eq([:to_s])
  end

  it 'does not retain references to subjects that do not have direct rules' do
    @ability.can :read, String

    @ability.can?(:read, 'foo')

    expect(@ability.instance_variable_get(:@rules_index)).not_to have_key('foo')
  end

  describe 'unauthorized message' do
    after(:each) do
      I18n.backend = nil
    end

    it 'uses action/subject in i18n' do
      I18n.backend.store_translations :en, unauthorized: { update: { array: 'foo' } }
      expect(@ability.unauthorized_message(:update, Array)).to eq('foo')
      expect(@ability.unauthorized_message(:update, [1, 2, 3])).to eq('foo')
      expect(@ability.unauthorized_message(:update, :missing)).to be_nil
    end

    it 'uses the aliases of an action given as a string in i18n' do
      I18n.backend.store_translations :en, unauthorized: { read: { array: 'foo' } }
      expect(@ability.unauthorized_message('index', Array)).to eq('foo')
    end

    it "uses model's name in i18n" do
      class Account
        include ActiveModel::Model
      end

      I18n.backend.store_translations :en,
                                      activemodel: { models: { account: 'english name' } },
                                      unauthorized: { update: { all: '%{subject}' } }
      I18n.backend.store_translations :ja,
                                      activemodel: { models: { account: 'japanese name' } },
                                      unauthorized: { update: { all: '%{subject}' } }

      I18n.with_locale(:en) do
        expect(@ability.unauthorized_message(:update, Account)).to eq('english name')
      end

      I18n.with_locale(:ja) do
        expect(@ability.unauthorized_message(:update, Account)).to eq('japanese name')
      end
    end

    it "uses action's name in i18n" do
      class Account
        include ActiveModel::Model
      end

      I18n.backend.store_translations :en,
                                      actions: { update: 'english name' },
                                      unauthorized: { update: { all: '%{action}' } }
      I18n.backend.store_translations :ja,
                                      actions: { update: 'japanese name' },
                                      unauthorized: { update: { all: '%{action}' } }

      I18n.with_locale(:en) do
        expect(@ability.unauthorized_message(:update, Account)).to eq('english name')
      end

      I18n.with_locale(:ja) do
        expect(@ability.unauthorized_message(:update, Account)).to eq('japanese name')
      end
    end

    it 'uses symbol as subject directly' do
      I18n.backend.store_translations :en, unauthorized: { has: { cheezburger: 'Nom nom nom. I eated it.' } }
      expect(@ability.unauthorized_message(:has, :cheezburger)).to eq('Nom nom nom. I eated it.')
    end

    it 'uses correct i18n keys when hashes are used' do
      # Hashes are sent as subject when using:
      # load_and_authorize_resource :blog
      # load_and_authorize_resource through: :blog
      # And subject for collection actions (ie: index) returns: { <Blog id:1> => Post(id:integer) }
      I18n.backend.store_translations :en, unauthorized: { update: { all: 'all', array: 'foo' } }
      expect(@ability.unauthorized_message(:update, Hash => Array)).to eq('foo')
    end

    it 'uses correct subject when hashes are used' do
      I18n.backend.store_translations :en, unauthorized: { manage: { all: '%<action>s %<subject>s' } }
      expect(@ability.unauthorized_message(:update, Hash => Array)).to eq('update array')
    end

    it "falls back to 'manage' and 'all'" do
      I18n.backend.store_translations :en, unauthorized: {
        manage: { all: 'manage all', array: 'manage array' },
        update: { all: 'update all', array: 'update array' }
      }
      expect(@ability.unauthorized_message(:update, Array)).to eq('update array')
      expect(@ability.unauthorized_message(:update, Hash)).to eq('update all')
      expect(@ability.unauthorized_message(:foo, Array)).to eq('manage array')
      expect(@ability.unauthorized_message(:foo, Hash)).to eq('manage all')
    end

    it 'follows aliased actions' do
      I18n.backend.store_translations :en, unauthorized: { modify: { array: 'modify array' } }
      @ability.alias_action :update, to: :modify
      expect(@ability.unauthorized_message(:update, Array)).to eq('modify array')
      expect(@ability.unauthorized_message(:edit, Array)).to eq('modify array')
    end

    it 'has variables for action and subject' do
      # old syntax for now in case testing with old I18n
      I18n.backend.store_translations :en, unauthorized: { manage: { all: '%<action>s %<subject>s' } }
      expect(@ability.unauthorized_message(:update, Array)).to eq('update array')
      expect(@ability.unauthorized_message(:update, ArgumentError)).to eq('update argument error')
      expect(@ability.unauthorized_message(:edit, 1..3)).to eq('edit range')
    end
  end

  describe '#merge' do
    it 'adds the rules from the given ability' do
      @ability.can :use, :tools
      (another_ability = double).extend(CanCan::Ability)
      another_ability.can :use, :search

      @ability.merge(another_ability)
      expect(@ability.can?(:use, :search)).to be(true)
      expect(@ability.send(:rules).size).to eq(2)
    end

    it 'adds the aliased actions from the given ability' do
      @ability.alias_action :show, to: :see
      (another_ability = double).extend(CanCan::Ability)
      another_ability.alias_action :create, :update, to: :modify

      @ability.merge(another_ability)
      expect(@ability.aliased_actions).to eq(
        read: %i[index show],
        create: %i[new],
        update: %i[edit],
        modify: %i[create update],
        see: %i[show]
      )
    end

    it 'overwrittes the aliased actions with the value from the given ability' do
      @ability.alias_action :show, :index, to: :see
      (another_ability = double).extend(CanCan::Ability)
      another_ability.alias_action :show, to: :see

      @ability.merge(another_ability)
      expect(@ability.aliased_actions).to eq(
        read: %i[index show],
        create: %i[new],
        update: %i[edit],
        see: %i[show]
      )
    end

    it 'expands the aliased actions from the given ability after a check' do
      @ability.can :modify, Integer
      expect(@ability.can?(:update, Integer)).to be(false)
      (another_ability = double).extend(CanCan::Ability)
      another_ability.alias_action :update, to: :modify

      @ability.merge(another_ability)
      expect(@ability.can?(:update, Integer)).to be(true)
    end

    it 'can add an empty ability' do
      (another_ability = double).extend(CanCan::Ability)

      @ability.merge(another_ability)
      expect(@ability.send(:rules).size).to eq(0)
    end

    it 'applies its own aliases to the rules of the given ability, even when they were already checked' do
      @ability.alias_action :increment, to: :modify
      (another_ability = double).extend(CanCan::Ability)
      another_ability.can :modify, :all
      expect(another_ability.can?(:increment, 123)).to be(false)

      @ability.merge(another_ability)
      expect(@ability.can?(:increment, 123)).to be(true)
    end

    it 'applies the aliases of the given ability to its own rules, even when they were already checked' do
      @ability.can :modify, :all
      expect(@ability.can?(:increment, 123)).to be(false)
      (another_ability = double).extend(CanCan::Ability)
      another_ability.alias_action :increment, to: :modify

      @ability.merge(another_ability)
      expect(@ability.can?(:increment, 123)).to be(true)
    end
  end

  describe 'when #can? is used with a Hash (nested resources)' do
    it 'is unauthorized with no rules' do
      expect(@ability.can?(:read, 1 => Symbol)).to be(false)
    end

    it 'is authorized when the child is authorized' do
      @ability.can :read, Symbol
      expect(@ability.can?(:read, 1 => Symbol)).to be(true)
    end

    it 'is authorized when the condition doesn\'t concern the parent' do
      @ability.can :read, Symbol, whatever: true
      expect(@ability.can?(:read, 1 => Symbol)).to be(true)
    end

    it 'verifies the parent against an equality condition' do
      @ability.can :read, Symbol, integer: 1
      expect(@ability.can?(:read, 1 => Symbol)).to be(true)
      expect(@ability.can?(:read, 2 => Symbol)).to be(false)
    end

    it 'verifies the parent against an array condition' do
      @ability.can :read, Symbol, integer: [0, 1]
      expect(@ability.can?(:read, 1 => Symbol)).to be(true)
      expect(@ability.can?(:read, 2 => Symbol)).to be(false)
    end

    it 'verifies the parent against a hash condition' do
      @ability.can :read, Symbol, integer: { to_i: 1 }
      expect(@ability.can?(:read, 1 => Symbol)).to be(true)
      expect(@ability.can?(:read, 2 => Symbol)).to be(false)
    end

    it 'is authorized when a cannot condition doesn\'t concern the parent' do
      @ability.can :read, Symbol
      @ability.cannot :read, Symbol, whatever: true
      expect(@ability.can?(:read, 1 => Symbol)).to be(true)
    end

    it 'verifies the parent against a cannot condition' do
      @ability.can :read, Symbol
      @ability.cannot :read, Symbol, integer: 1
      expect(@ability.can?(:read, 1 => Symbol)).to be(false)
      expect(@ability.can?(:read, 2 => Symbol)).to be(true)
    end
  end
end
