#!/usr/bin/env ruby

require "autoproj/cli/inspection_tool"

root = File.expand_path("..", __dir__)
Dir.chdir(root)
ENV["AUTOPROJ_CURRENT_ROOT"] = root

workspace = Autoproj::Workspace.default
workspace.config.interactive = false
inspection = Autoproj::CLI::InspectionTool.new(workspace)
inspection.initialize_and_load(read_only: true)

exit 0 unless workspace.config.get("rtt_corba_implementation") == "none"

inspection.finalize_setup(
  ["rtt"],
  non_imported_packages: :return,
  recursive: true,
  read_only: true
)

rtt = workspace.manifest.find_autobuild_package("rtt")
abort "resolved Autoproj graph does not contain rtt" unless rtt

resolved_dependencies = rtt.dependencies.to_a +
                        rtt.optional_dependencies.to_a +
                        rtt.os_packages.to_a +
                        rtt.description.dependencies.map(&:name)

if resolved_dependencies.include?("omniorb")
  abort "rtt resolved omniorb even though rtt_corba_implementation is none"
end
