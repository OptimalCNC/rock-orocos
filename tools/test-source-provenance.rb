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

errors = OrocosRock::SourceProvenance.validate(ROOT)
raise errors.join("\n") unless errors.empty?

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

puts "Source provenance tests passed."
