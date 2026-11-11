# frozen_string_literal: true

require_relative 'lib/waservix'

Gem::Specification.new do |s|
  s.name        = 'waservix'
  s.version     = WAservix::VERSION
  s.summary     = 'WAservix WhatsApp API Gateway: official Ruby client by Tekservix'
  s.description = 'WAservix WhatsApp API Gateway. Send WhatsApp messages, images and documents from your own number with WAservix: status tracking, contacts, groups and webhooks. Works in Rails, Sinatra and plain Ruby.'
  s.authors     = ['Tekservix']
  s.email       = 'support@tekservix.com'
  s.homepage    = 'https://tekservix.com/waservix/'
  s.license     = 'MIT'
  s.files       = Dir['lib/**/*.rb'] + %w[README.md LICENSE]
  s.required_ruby_version = '>= 2.7'
  s.metadata = {
    'homepage_uri' => 'https://tekservix.com/waservix/',
    'documentation_uri' => 'https://tekservix.com/waservix/docs/',
    'source_code_uri' => 'https://github.com/TekservixHQ/waservix-ruby',
    'bug_tracker_uri' => 'https://github.com/TekservixHQ/waservix-ruby/issues',
    'rubygems_mfa_required' => 'true'
  }
end
