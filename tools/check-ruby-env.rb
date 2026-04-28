#!/usr/bin/env ruby

require "open3"
require "rbconfig"

root = File.expand_path("..", __dir__)
gem_home = File.join(root, ".autoproj", "gems", "ruby", RbConfig::CONFIG.fetch("ruby_version"))

env = {
  "GEM_HOME" => gem_home,
  "GEM_PATH" => "",
  "BUNDLE_GEMFILE" => nil
}

code = <<~'RUBY'
  gem "facets", "< 3.2"
  require "facets/module/spacename"
  gem "backports"
  require "backports/2.4.0/true_class/dup"
  puts "facets #{Gem.loaded_specs.fetch("facets").version}"
  puts "backports #{Gem.loaded_specs.fetch("backports").version}"
RUBY

stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, "-e", code)

if status.success?
  puts stdout
  puts "required Ruby gems available in #{gem_home}"
else
  warn "workspace Ruby gems are incomplete for isolated Autoproj builds"
  warn "GEM_HOME=#{gem_home}"
  warn stderr
  exit status.exitstatus || 1
end
