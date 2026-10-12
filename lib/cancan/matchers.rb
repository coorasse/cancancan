# frozen_string_literal: true

require 'rspec/core'
require 'rspec/expectations'

RSpec::Matchers.define :be_able_to do |*args|
  match do |ability|
    actions = args.first
    if actions.is_a? Array
      if actions.empty?
        false
      else
        actions.all? { |action| ability.can?(action, *args[1..-1]) }
      end
    else
      ability.can?(*args)
    end
  end

  match_when_negated do |ability|
    actions = args.first
    if actions.is_a? Array
      raise CanCan::ImplementationRemoved, '`expect(...).not_to be_able_to(:action_a, :action_b)` is not supported: ' \
                                           'it passes as soon as one action is forbidden, which is ambiguous. ' \
                                           'Write one expectation per action instead.'
    else
      !ability.can?(*args)
    end
  end

  failure_message do
    resource = args[1]
    if resource.instance_of?(Class)
      "expected to be able to #{args.join(' ')}"
    else
      "expected to be able to #{args.map(&:inspect).join(' ')}"
    end
  end

  failure_message_when_negated do
    resource = args[1]
    if resource.instance_of?(Class)
      "expected not to be able to #{args.join(' ')}"
    else
      "expected not to be able to #{args.map(&:inspect).join(' ')}"
    end
  end

  description do
    "be able to #{args.join(' ')}"
  end
end
