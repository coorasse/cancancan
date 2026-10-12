# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'cancan/version'

Gem::Specification.new do |s|
  s.name        = 'cancancan'
  s.version     = CanCan::VERSION
  s.authors     = ['Alessandro Rodi (Renuo AG)', 'Bryan Rite', 'Ryan Bates', 'Richard Wilson']
  s.email       = 'alessandro.rodi@renuo.ch'
  s.homepage    = 'https://github.com/CanCanCommunity/cancancan'
  s.metadata = { 'changelog_uri' => 'https://github.com/CanCanCommunity/cancancan/blob/main/CHANGELOG.md',
                 'funding_uri' => 'https://github.com/sponsors/coorasse' }
  s.summary     = 'Simple authorization solution for Rails.'
  s.description = 'Simple authorization solution for Rails. All permissions are stored in a single location.'
  s.platform    = Gem::Platform::RUBY
  s.license     = 'MIT'

  s.files       = `git ls-files lib cancancan.gemspec`.split($INPUT_RECORD_SEPARATOR)
  s.require_paths = ['lib']

  s.required_ruby_version = '>= 3.2.0'
end
