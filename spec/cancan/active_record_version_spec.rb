# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Active Record version check' do
  let(:entry_point) { File.expand_path('../../lib/cancan.rb', __dir__) }

  it 'raises an error when Active Record is older than 8.0' do
    allow(ActiveRecord).to receive(:version).and_return(Gem::Version.new('7.2.2'))

    expect { load entry_point }.to raise_error(
      CanCan::Error,
      'cancancan 4 requires Active Record 8.0 or later; use cancancan 3.x with Active Record 7.2.2'
    )
  end

  it 'loads with Active Record 8.0 or later' do
    allow(ActiveRecord).to receive(:version).and_return(Gem::Version.new('8.0.0.beta1'))

    expect { load entry_point }.not_to raise_error
  end
end
