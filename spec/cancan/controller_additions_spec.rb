# frozen_string_literal: true

require 'spec_helper'

describe CanCan::ControllerAdditions do
  before(:each) do
    @controller_class = Class.new
    @controller = @controller_class.new
    allow(@controller).to receive(:params) { {} }
    allow(@controller).to receive(:current_user) { :current_user }
    expect(@controller_class).to receive(:helper_method).with(:can?, :cannot?, :current_ability)
    @controller_class.send(:include, CanCan::ControllerAdditions)
  end

  it 'authorize! assigns @_authorized instance variable and pass args to current ability' do
    allow(@controller.current_ability).to receive(:authorize!).with(:foo, :bar)
    @controller.authorize!(:foo, :bar)
    expect(@controller.instance_variable_get(:@_authorized)).to be(true)
  end

  it 'has a current_ability method which generates an ability for the current user' do
    expect(@controller.current_ability).to be_kind_of(Ability)
  end

  it 'provides a can? and cannot? methods which go through the current ability' do
    expect(@controller.current_ability).to be_kind_of(Ability)
    expect(@controller.can?(:foo, :bar)).to be(false)
    expect(@controller.cannot?(:foo, :bar)).to be(true)
  end

  it 'load_and_authorize_resource setups a before filter which passes call to ControllerResource' do
    expect(cancan_resource_class = double).to receive(:load_and_authorize_resource)
    allow(CanCan::ControllerResource).to receive(:new).with(@controller, nil, { foo: :bar }) { cancan_resource_class }
    expect(@controller_class)
      .to receive(:before_action).with({}) { |_options, &block| block.call(@controller) }
    @controller_class.load_and_authorize_resource foo: :bar
  end

  it 'load_and_authorize_resource properly passes first argument as the resource name' do
    expect(cancan_resource_class = double).to receive(:load_and_authorize_resource)
    allow(CanCan::ControllerResource).to receive(:new).with(@controller, :project, { foo: :bar }) do
      cancan_resource_class
    end
    expect(@controller_class)
      .to receive(:before_action).with({}) { |_options, &block| block.call(@controller) }
    @controller_class.load_and_authorize_resource :project, foo: :bar
  end

  it 'load_and_authorize_resource with :prepend prepends the before filter' do
    expect(@controller_class).to receive(:prepend_before_action).with({})
    @controller_class.load_and_authorize_resource foo: :bar, prepend: true
  end

  it 'authorize_resource setups a before filter which passes call to ControllerResource' do
    expect(cancan_resource_class = double).to receive(:authorize_resource)
    allow(CanCan::ControllerResource).to receive(:new).with(@controller, nil, { foo: :bar }) { cancan_resource_class }
    expect(@controller_class)
      .to receive(:before_action).with({ except: :show, if: true }) do |_options, &block|
        block.call(@controller)
      end
    @controller_class.authorize_resource foo: :bar, except: :show, if: true
  end

  it 'load_resource setups a before filter which passes call to ControllerResource' do
    expect(cancan_resource_class = double).to receive(:load_resource)
    allow(CanCan::ControllerResource).to receive(:new).with(@controller, nil, { foo: :bar }) { cancan_resource_class }
    expect(@controller_class)
      .to receive(:before_action).with({ only: %i[show index], unless: false }) do |_options, &block|
        block.call(@controller)
      end
    @controller_class.load_resource foo: :bar, only: %i[show index], unless: false
  end

  it 'skip_authorization_check setups a before filter which sets @_authorized to true' do
    expect(@controller_class)
      .to receive(:before_action).with(:filter_options) { |_options, &block| block.call(@controller) }
    @controller_class.skip_authorization_check(:filter_options)
    expect(@controller.instance_variable_get(:@_authorized)).to be(true)
  end

  it 'check_authorization triggers AuthorizationNotPerformed in after filter' do
    expect(@controller_class)
      .to receive(:after_action).with({ only: [:test] }) { |_options, &block| block.call(@controller) }
    expect do
      @controller_class.check_authorization({ only: [:test] })
    end.to raise_error(CanCan::AuthorizationNotPerformed)
  end

  it 'check_authorization does not trigger AuthorizationNotPerformed when :if is false' do
    allow(@controller).to receive(:check_auth?) { false }
    allow(@controller_class)
      .to receive(:after_action).with({}) { |_options, &block| block.call(@controller) }
    expect do
      @controller_class.check_authorization(if: :check_auth?)
    end.not_to raise_error
  end

  it 'check_authorization does not trigger AuthorizationNotPerformed when :unless is true' do
    allow(@controller).to receive(:engine_controller?) { true }
    expect(@controller_class)
      .to receive(:after_action).with({}) { |_options, &block| block.call(@controller) }
    expect do
      @controller_class.check_authorization(unless: :engine_controller?)
    end.not_to raise_error
  end

  it 'check_authorization does not raise error when @_authorized is set' do
    @controller.instance_variable_set(:@_authorized, true)
    expect(@controller_class)
      .to receive(:after_action).with({ only: [:test] }) { |_options, &block| block.call(@controller) }
    expect do
      @controller_class.check_authorization(only: [:test])
    end.not_to raise_error
  end

  it 'cancan_resource_class is ControllerResource by default' do
    expect(@controller.class.cancan_resource_class).to eq(CanCan::ControllerResource)
  end

  it 'cancan_skipper is an empty hash with :authorize and :load options and remember changes' do
    expect(@controller_class.cancan_skipper).to eq(authorize: {}, load: {})
    @controller_class.cancan_skipper[:load] = true
    expect(@controller_class.cancan_skipper[:load]).to be(true)
  end

  it 'skip_authorize_resource adds itself to the cancan skipper with given model name and options' do
    @controller_class.skip_authorize_resource(:project, only: %i[index show])
    expect(@controller_class.cancan_skipper[:authorize][:project]).to eq(only: %i[index show])
    @controller_class.skip_authorize_resource(only: %i[index show])
    expect(@controller_class.cancan_skipper[:authorize][nil]).to eq(only: %i[index show])
    @controller_class.skip_authorize_resource(:article)
    expect(@controller_class.cancan_skipper[:authorize][:article]).to eq({})
    @controller_class.skip_authorize_resource(:article, if: -> {})
    expect(@controller_class.cancan_skipper[:authorize][:article]).to have_key(:if)
    @controller_class.skip_authorize_resource(:article, unless: -> {})
    expect(@controller_class.cancan_skipper[:authorize][:article]).to have_key(:unless)
  end

  it 'skip_load_resource adds itself to the cancan skipper with given model name and options' do
    @controller_class.skip_load_resource(:project, only: %i[index show])
    expect(@controller_class.cancan_skipper[:load][:project]).to eq(only: %i[index show])
    @controller_class.skip_load_resource(only: %i[index show])
    expect(@controller_class.cancan_skipper[:load][nil]).to eq(only: %i[index show])
    @controller_class.skip_load_resource(:article)
    expect(@controller_class.cancan_skipper[:load][:article]).to eq({})
    @controller_class.skip_load_resource(:article, if: -> {})
    expect(@controller_class.cancan_skipper[:load][:article]).to have_key(:if)
    @controller_class.skip_load_resource(:article, unless: -> {})
    expect(@controller_class.cancan_skipper[:load][:article]).to have_key(:unless)
  end

  it 'skip_load_and_authorize_resource adds itself to the cancan skipper with a string model name as a symbol' do
    @controller_class.skip_load_and_authorize_resource('project')
    expect(@controller_class.cancan_skipper[:load][:project]).to eq({})
    expect(@controller_class.cancan_skipper[:authorize][:project]).to eq({})
  end

  it 'skip_load_and_authorize_resource adds itself to the cancan skipper with given model name and options' do
    @controller_class.skip_load_and_authorize_resource(:project, only: %i[index show])
    expect(@controller_class.cancan_skipper[:load][:project]).to eq(only: %i[index show])
    expect(@controller_class.cancan_skipper[:authorize][:project]).to eq(only: %i[index show])
  end

  describe 'when inheriting' do
    before(:each) do
      @super_controller_class = Class.new
      @super_controller = @super_controller_class.new

      @sub_controller_class = Class.new(@super_controller_class)
      @sub_controller = @sub_controller_class.new

      allow(@super_controller_class).to receive(:helper_method)
      @super_controller_class.send(:include, CanCan::ControllerAdditions)
      @super_controller_class.skip_load_and_authorize_resource(only: %i[index show])
    end

    it 'sub_classes should skip the same behaviors and actions as super_classes' do
      expect(@super_controller_class.cancan_skipper[:load][nil]).to eq(only: %i[index show])
      expect(@super_controller_class.cancan_skipper[:authorize][nil]).to eq(only: %i[index show])

      expect(@sub_controller_class.cancan_skipper[:load][nil]).to eq(only: %i[index show])
      expect(@sub_controller_class.cancan_skipper[:authorize][nil]).to eq(only: %i[index show])
    end

    it 'does not change the super_class or sibling classes when a sub_class skips' do
      sibling_controller_class = Class.new(@super_controller_class)

      @sub_controller_class.skip_authorize_resource(:project)
      @sub_controller_class.skip_load_resource(:project)

      expect(@sub_controller_class.cancan_skipper[:authorize][:project]).to eq({})
      expect(@sub_controller_class.cancan_skipper[:load][:project]).to eq({})
      [@super_controller_class, sibling_controller_class].each do |controller_class|
        expect(controller_class.cancan_skipper[:authorize]).not_to have_key(:project)
        expect(controller_class.cancan_skipper[:load]).not_to have_key(:project)
      end
    end

    it 'does not change the super_class when its skipper was read before a sub_class skips' do
      controller_class = Class.new
      allow(controller_class).to receive(:helper_method)
      controller_class.send(:include, CanCan::ControllerAdditions)
      sub_controller_class = Class.new(controller_class)
      controller_class.cancan_skipper

      sub_controller_class.skip_authorize_resource

      expect(sub_controller_class.cancan_skipper[:authorize][nil]).to eq({})
      expect(controller_class.cancan_skipper[:authorize]).not_to have_key(nil)
    end
  end
end
