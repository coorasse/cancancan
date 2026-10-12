# frozen_string_literal: true

require 'spec_helper'

describe 'be_able_to' do
  subject { double }

  context 'check single ability' do
    it 'delegates to can?' do
      is_expected.to receive(:can?).with(:read, 123) { true }
      is_expected.to be_able_to(:read, 123)
    end

    it 'reports a nice failure message for should' do
      is_expected.to receive(:can?).with(:read, 123) { false }
      expect do
        is_expected.to be_able_to(:read, 123)
      end.to raise_error('expected to be able to :read 123')
    end

    it 'reports a nice failure message for should not' do
      is_expected.to receive(:can?).with(:read, 123) { true }
      expect do
        is_expected.to_not be_able_to(:read, 123)
      end.to raise_error('expected not to be able to :read 123')
    end

    it 'delegates additional arguments to can? and reports in failure message' do
      is_expected.to receive(:can?).with(:read, 123, 456) { false }
      expect do
        is_expected.to be_able_to(:read, 123, 456)
      end.to raise_error('expected to be able to :read 123 456')
    end
  end

  context 'check array of abilities' do
    it 'delegates to can? with array of abilities with one action' do
      is_expected.to receive(:can?).with(:read, 123) { true }
      is_expected.to be_able_to([:read], 123)
    end

    it 'delegates to can? with array of abilities with multiple actions' do
      is_expected.to receive(:can?).with(:read, 123) { true }
      is_expected.to receive(:can?).with(:update, 123) { true }
      is_expected.to be_able_to(%i[read update], 123)
    end

    it 'raises an error when negated with an empty array of actions' do
      expect { is_expected.not_to be_able_to([], 123) }.to raise_error(CanCan::ImplementationRemoved)
    end

    it 'raises an error when negated with several actions' do
      expect { is_expected.not_to be_able_to(%i[read update], 123) }.to raise_error(CanCan::ImplementationRemoved)
    end
  end
end
