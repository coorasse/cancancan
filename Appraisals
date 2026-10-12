# frozen_string_literal: true

%w[8.0.0 8.1.0].each do |version|
  appraise "activerecord_#{version}" do
    gem 'actionpack', "~> #{version}", require: 'action_pack'
    gem 'activerecord', "~> #{version}", require: 'active_record'
    gem 'activesupport', "~> #{version}", require: 'active_support/all'

    platforms :jruby do
      gem 'activerecord-jdbcsqlite3-adapter'
      gem 'jdbc-sqlite3'
      gem 'jdbc-postgres'
    end

    platforms :ruby, :windows do
      gem 'pg'
      gem 'sqlite3', '>= 2.1'
    end
  end
end

appraise 'activerecord_main' do
  git 'https://github.com/rails/rails', branch: 'main' do
    gem 'actionpack', require: 'action_pack'
    gem 'activerecord', require: 'active_record'
    gem 'activesupport', require: 'active_support/all'
  end

  platforms :jruby do
    gem 'activerecord-jdbcsqlite3-adapter'
    gem 'jdbc-sqlite3'
    gem 'jdbc-postgres'
  end

  platforms :ruby, :windows do
    gem 'pg'
    gem 'sqlite3', '>= 2.1'
  end
end
