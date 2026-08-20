#!/usr/bin/env ruby

require "json"
require "yaml"

module OrocosRock
  module SourceProvenance
    SOURCE_ORGANIZATION = "liufang-robot"

    FIRST_PARTY_REPOSITORIES = {
      "farbot" => "farbot",
      "rtlog-cpp" => "rtlog-cpp",
      "rtt" => "rtt",
      "rtt_opcua" => "rtt_opcua",
      "ocl" => "ocl",
      "utilmm" => "utilmm",
      "typelib" => "tools-typelib",
      "rtt_typelib" => "tools-rtt_typelib",
      "orogen" => "tools-orogen"
    }.transform_values do |repository|
      "https://github.com/#{SOURCE_ORGANIZATION}/#{repository}.git"
    end.freeze

    THIRD_PARTY_REPOSITORIES = {
      "open62541" => "https://github.com/open62541/open62541.git",
      "open62541pp" => "https://github.com/open62541pp/open62541pp.git",
      "utilrb" => "https://github.com/rock-core/tools-utilrb.git",
      "metaruby" => "https://github.com/rock-core/tools-metaruby.git",
      "vcpkg" => "https://github.com/microsoft/vcpkg.git"
    }.freeze

    WINDOWS_PARAMETERS = {
      "farbot" => "FarbotRepository",
      "rtlog-cpp" => "RtlogRepository",
      "rtt" => "RttRepository",
      "open62541" => "Open62541Repository",
      "open62541pp" => "Open62541ppRepository",
      "rtt_opcua" => "RttOpcuaRepository",
      "ocl" => "OclRepository",
      "utilmm" => "UtilmmRepository",
      "typelib" => "TypelibRepository",
      "rtt_typelib" => "RttTypelibRepository",
      "utilrb" => "UtilrbRepository",
      "metaruby" => "MetarubyRepository",
      "orogen" => "OrogenRepository",
      "vcpkg" => "VcpkgRepository"
    }.freeze

    AUTOPROJ_PACKAGES = %w[
      farbot rtlog-cpp open62541 open62541pp rtt rtt_opcua ocl orogen
      typelib utilmm rtt_typelib
    ].freeze

    module_function

    def validate(root)
      errors = []
      repositories = FIRST_PARTY_REPOSITORIES.merge(THIRD_PARTY_REPOSITORIES)
      check_autoproj(root, repositories, errors)
      check_source_lock(root, repositories, errors)
      check_windows_defaults(root, repositories, errors)
      check_package_set(root, errors)
      errors
    rescue JSON::ParserError, Psych::SyntaxError, KeyError => e
      ["source provenance input is invalid: #{e.message}"]
    end

    def check_autoproj(root, repositories, errors)
      selection = YAML.safe_load_file(File.join(root, "autoproj", "overrides.yml"))
      entries = selection.fetch("version_control", []) + selection.fetch("overrides", [])
      AUTOPROJ_PACKAGES.each do |package|
        entry = entries.find { |candidate| candidate.key?(package) }
        actual = entry && entry["url"]
        expected = repositories.fetch(package)
        errors << "autoproj source #{package}: expected #{expected}, got #{actual.inspect}" unless actual == expected
      end
    end

    def check_source_lock(root, repositories, errors)
      document = JSON.parse(File.read(File.join(root, "packaging", "source-lock.json")))
      actual = document.fetch("sources").to_h { |source| [source.fetch("name"), source.fetch("repository")] }
      unknown = actual.keys - repositories.keys
      unless unknown.empty?
        errors << "source lock contains unexpected source(s): #{unknown.sort.join(', ')}"
      end
      repositories.each do |package, expected|
        errors << "source lock #{package}: expected #{expected}, got #{actual[package].inspect}" unless actual[package] == expected
      end
    end

    def check_windows_defaults(root, repositories, errors)
      script = File.read(File.join(root, "tools", "build-windows-msvc.ps1"))
      WINDOWS_PARAMETERS.each do |package, parameter|
        expected = repositories.fetch(package)
        token = %([string]$#{parameter} = "#{expected}")
        errors << "Windows default #{parameter}: expected #{expected}" unless script.include?(token)
      end
    end

    def check_package_set(root, errors)
      manifest = YAML.safe_load_file(File.join(root, "autoproj", "manifest"))
      package_sets = manifest.fetch("package_sets")
      expected = "https://github.com/rock-core/package_set.git"
      actual = package_sets.first && package_sets.first["url"]
      errors << "Autoproj package set: expected #{expected}, got #{actual.inspect}" unless actual == expected
    end
  end
end

if $PROGRAM_NAME == __FILE__
  root = File.expand_path("..", __dir__)
  errors = OrocosRock::SourceProvenance.validate(root)
  unless errors.empty?
    warn errors.join("\n")
    exit 1
  end
end
