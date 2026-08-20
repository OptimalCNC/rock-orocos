#!/usr/bin/env ruby

require "fileutils"
require "tmpdir"
require_relative "check-source-provenance"

ROOT = File.expand_path("..", __dir__)
FIXTURE_PATHS = %w[
  autoproj/manifest
  autoproj/overrides.yml
  packaging/source-lock.json
  tools/build-windows-msvc.ps1
].freeze

def assert_includes(errors, text)
  return if errors.any? { |error| error.include?(text) }

  raise "expected an error containing #{text.inspect}, got #{errors.inspect}"
end

def record_missing_error(accepted_bypasses, name, errors, text)
  return if errors.any? { |error| error.include?(text) }

  accepted_bypasses << name
end

def with_fixture
  Dir.mktmpdir("orocos-source-provenance-") do |root|
    FIXTURE_PATHS.each do |relative|
      destination = File.join(root, relative)
      FileUtils.mkdir_p(File.dirname(destination))
      FileUtils.cp(File.join(ROOT, relative), destination)
    end
    yield root
  end
end

def mutate_yaml(root, relative_path)
  path = File.join(root, relative_path)
  document = YAML.safe_load_file(path)
  yield document
  File.write(path, YAML.dump(document))
end

errors = OrocosRock::SourceProvenance.validate(ROOT)
raise errors.join("\n") unless errors.empty?

accepted_bypasses = []

with_fixture do |root|
  path = File.join(root, "autoproj", "overrides.yml")
  expected = OrocosRock::SourceProvenance::FIRST_PARTY_REPOSITORIES.fetch("farbot")
  File.write(path, File.read(path).sub(expected, "https://github.com/wrong-owner/farbot.git"))
  assert_includes(OrocosRock::SourceProvenance.validate(root), "autoproj source farbot")
end

with_fixture do |root|
  path = File.join(root, "packaging", "source-lock.json")
  expected = OrocosRock::SourceProvenance::FIRST_PARTY_REPOSITORIES.fetch("rtt")
  File.write(path, File.read(path).sub(expected, "https://github.com/wrong-owner/rtt.git"))
  assert_includes(OrocosRock::SourceProvenance.validate(root), "source lock rtt")
end

with_fixture do |root|
  path = File.join(root, "tools", "build-windows-msvc.ps1")
  expected = OrocosRock::SourceProvenance::FIRST_PARTY_REPOSITORIES.fetch("ocl")
  File.write(path, File.read(path).sub(expected, "https://github.com/wrong-owner/ocl.git"))
  assert_includes(OrocosRock::SourceProvenance.validate(root), "Windows default OclRepository")
end

with_fixture do |root|
  path = File.join(root, "packaging", "source-lock.json")
  expected = OrocosRock::SourceProvenance::THIRD_PARTY_REPOSITORIES.fetch("open62541")
  File.write(path, File.read(path).sub(expected, "https://github.com/wrong-owner/open62541.git"))
  assert_includes(OrocosRock::SourceProvenance.validate(root), "source lock open62541")
end

with_fixture do |root|
  mutate_yaml(root, "autoproj/overrides.yml") do |document|
    document.fetch("overrides") << {
      "rtt" => nil,
      "type" => "git",
      "url" => "https://github.com/wrong-owner/rtt.git",
      "branch" => "dev"
    }
  end
  record_missing_error(
    accepted_bypasses,
    "later duplicate source override",
    OrocosRock::SourceProvenance.validate(root),
    "autoproj overrides contains duplicate selector rtt"
  )
end

with_fixture do |root|
  mutate_yaml(root, "autoproj/overrides.yml") do |document|
    document.fetch("overrides") << {
      ".*" => nil,
      "type" => "git",
      "url" => "https://github.com/wrong-owner/everything.git"
    }
  end
  record_missing_error(
    accepted_bypasses,
    "broad source matcher",
    OrocosRock::SourceProvenance.validate(root),
    "autoproj overrides contains unauthorized selector .*"
  )
end

with_fixture do |root|
  mutate_yaml(root, "autoproj/overrides.yml") do |document|
    document.fetch("overrides").reject! { |entry| entry.key?("utilrb") }
  end
  record_missing_error(
    accepted_bypasses,
    "missing utilrb override",
    OrocosRock::SourceProvenance.validate(root),
    "autoproj overrides is missing approved selector utilrb"
  )
end

with_fixture do |root|
  mutate_yaml(root, "autoproj/overrides.yml") do |document|
    document.fetch("overrides").reject! { |entry| entry.key?("tools/metaruby") }
  end
  record_missing_error(
    accepted_bypasses,
    "missing metaruby override",
    OrocosRock::SourceProvenance.validate(root),
    "autoproj overrides is missing approved selector tools/metaruby"
  )
end

with_fixture do |root|
  mutate_yaml(root, "autoproj/overrides.yml") do |document|
    document.fetch("overrides") << {
      "utilrb" => nil,
      "type" => "git",
      "url" => "https://github.com/wrong-owner/tools-utilrb.git",
      "branch" => "master"
    }
  end
  record_missing_error(
    accepted_bypasses,
    "utilrb redirect",
    OrocosRock::SourceProvenance.validate(root),
    "autoproj source utilrb"
  )
end

with_fixture do |root|
  mutate_yaml(root, "autoproj/overrides.yml") do |document|
    document.fetch("overrides") << {
      "tools/metaruby" => nil,
      "type" => "git",
      "url" => "https://github.com/wrong-owner/tools-metaruby.git",
      "branch" => "master"
    }
  end
  record_missing_error(
    accepted_bypasses,
    "metaruby redirect",
    OrocosRock::SourceProvenance.validate(root),
    "autoproj source metaruby"
  )
end

with_fixture do |root|
  mutate_yaml(root, "autoproj/manifest") do |document|
    document.fetch("package_sets") << {
      "type" => "git",
      "url" => "https://github.com/wrong-owner/package-set.git"
    }
  end
  record_missing_error(
    accepted_bypasses,
    "extra package set",
    OrocosRock::SourceProvenance.validate(root),
    "Autoproj package sets must equal the approved list"
  )
end

unless accepted_bypasses.empty?
  raise "source provenance accepted unsafe mutation(s): #{accepted_bypasses.join(', ')}"
end

puts "Source provenance tests passed."
