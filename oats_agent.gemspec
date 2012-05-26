# -*- encoding: utf-8 -*-
require File.expand_path('../lib/oats_agent/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Levent Atasoy"]
  gem.email         = ["levent.atasoy@gmail.com"]
  gem.description   = %q{With this gem OATS can start in agent mode in the background so that it can communicate with OCC.}
  gem.summary       = gem.description.dup
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "oats_agent"
  gem.require_paths = ["lib"]
  gem.version       = OatsAgent::VERSION
  
  gem.add_dependency 'oats'
  gem.add_dependency 'log4r'

  
  gem.add_dependency 'json'
  gem.add_dependency 'em-http-request'
  if RUBY_PLATFORM =~ /linux/ # Seems to be needed by Ubuntu
    gem.add_dependency 'execjs'
    gem.add_dependency 'therubyracer'
  end
end
