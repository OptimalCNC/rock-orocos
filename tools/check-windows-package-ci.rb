#!/usr/bin/env ruby

require "yaml"

root = File.expand_path("..", __dir__)
workflow_path = File.join(root, ".github", "workflows", "windows-packages.yml")
staging_path = File.join(root, "tools", "prepare-windows-conda-release.ps1")
consumer_path = File.join(root, "tools", "test-windows-conda-consumer.ps1")
errors = []

unless File.file?(workflow_path)
  errors << "missing .github/workflows/windows-packages.yml"
else
  contents = File.read(workflow_path)
  workflow = YAML.safe_load(contents, aliases: true)
  triggers = workflow["on"] || workflow[true]
  jobs = workflow.fetch("jobs", {})
  build = jobs.fetch("build-packages", {})
  publish = jobs.fetch("publish-packages", {})

  unless triggers.is_a?(Hash)
    errors << "Windows package CI must define structured workflow triggers"
    triggers = {}
  end

  pull_request = triggers.fetch("pull_request", {}) || {}
  push = triggers.fetch("push", {}) || {}
  release = triggers.fetch("release", {}) || {}
  errors << "Windows package CI must run on pull requests" unless triggers.key?("pull_request")
  errors << "Windows package CI must run on pushes" unless triggers.key?("push")
  errors << "Windows package CI pushes must be limited to main" unless Array(push["branches"]) == ["main"]
  errors << "Windows package CI must build on manual dispatch" unless triggers.key?("workflow_dispatch")
  unless triggers.key?("release") && Array(release["types"]) == ["published"]
    errors << "Windows package CI must use the published release event"
  end

  required_paths = %w[
    .github/workflows/windows-packages.yml
    packaging/**
    tools/build-windows-msvc.ps1
    tools/check-windows-package-ci.rb
    tools/prepare-windows-conda-release.ps1
    tools/test-windows-conda-consumer.ps1
    tools/test-windows-source-lock.ps1
    tools/windows-source-lock.ps1
    pixi.toml
    pixi.lock
  ]
  {
    "pull requests" => Array(pull_request["paths"]),
    "main pushes" => Array(push["paths"])
  }.each do |trigger_name, paths|
    required_paths.each do |path|
      errors << "Windows package CI #{trigger_name} must watch #{path}" unless paths.include?(path)
    end
    errors << "Windows package CI must not rebuild for docs-only changes" if paths.any? { |path| path.start_with?("docs/") }
  end

  top_permissions = workflow.fetch("permissions", {})
  unless top_permissions == { "contents" => "read" }
    errors << "Windows package CI top-level permissions must be contents: read only"
  end
  errors << "Windows package CI must use the canonical Prefix channel" unless workflow.dig("env", "PREFIX_CHANNEL") == "liufang-robot/orocos"
  errors << "Windows package CI channel must not contain @" if workflow.dig("env", "PREFIX_CHANNEL").to_s.include?("@")
  unless workflow.dig("env", "PUBLIC_CHANNEL_URL") == "https://prefix.dev/liufang-robot/orocos"
    errors << "Windows package CI must define the public consumer channel URL"
  end

  unless build["runs-on"] == "windows-2022" && build["timeout-minutes"].to_i >= 180
    errors << "Windows package build must use windows-2022 with a release-sized timeout"
  end
  build_steps = Array(build["steps"])
  build_runs = build_steps.filter_map { |step| step["run"] }.join("\n")
  build_uses = build_steps.filter_map { |step| step["uses"] }
  errors << "Windows package build must set up MSVC x64" unless build_uses.include?("ilammy/msvc-dev-cmd@v1") && contents.include?("arch: x64")
  errors << "Windows package build must install the locked package environment" unless contents.include?("environments: package") && contents.include?("locked: true")
  errors << "Windows package build must test the source lock" unless build_runs.include?("tools/test-windows-source-lock.ps1")
  errors << "Windows package build must render the recipe" unless build_runs.include?("pixi run --locked package-render")
  errors << "Windows package build must build and test both packages" unless build_runs.include?("pixi run --locked package-build")
  errors << "Windows package build must prepare a verified release bundle" unless build_runs.include?("tools/prepare-windows-conda-release.ps1") && build_runs.include?("-Mode Stage")
  errors << "Windows package build must test clean local-channel consumers" unless build_runs.include?("tools/test-windows-conda-consumer.ps1") && build_runs.include?("-LocalChannelPath packaging/conda/output")
  errors << "Windows package build must retain the verified bundle" unless build_uses.include?("actions/upload-artifact@v7") && contents.include?("if-no-files-found: error")
  errors << "Windows package build must retain failure diagnostics" unless build_steps.any? { |step| step["if"] == "failure()" && step["uses"] == "actions/upload-artifact@v7" }
  errors << "Windows package build must not hide failures" if build["continue-on-error"] == true

  publish_condition = publish["if"].to_s
  errors << "Prefix publication must depend on the verified build" unless publish["needs"] == "build-packages"
  errors << "Prefix publication must be release-only" unless publish_condition.include?("github.event_name == 'release'") && publish_condition.include?("github.event.action == 'published'")
  errors << "Prefix publication must reject prereleases" unless publish_condition.include?("github.event.release.prerelease == false")
  unless publish_condition.include?("github.repository == 'liufang-robot/rock-orocos'")
    errors << "Prefix publication must be limited to the canonical GitHub repository"
  end
  unless publish.fetch("permissions", {}) == { "contents" => "read", "id-token" => "write" }
    errors << "Prefix publication must grant only contents: read and id-token: write"
  end
  errors << "OIDC write permission must exist only in the publish job" unless contents.scan(/^\s+id-token:\s+write\s*$/).count == 1

  publish_steps = Array(publish["steps"])
  publish_runs = publish_steps.filter_map { |step| step["run"] }.join("\n")
  publish_uses = publish_steps.filter_map { |step| step["uses"] }
  errors << "Prefix publication must download the verified bundle" unless publish_uses.include?("actions/download-artifact@v8")
  unless publish_runs.include?("-Mode Verify") &&
         publish_runs.include?("github.event.release.tag_name") &&
         publish_runs.include?("-ExpectedRepositoryCommit")
    errors << "Prefix publication must verify the tag, commit, metadata, and checksums"
  end
  unless publish_runs.include?("rattler-build upload prefix") &&
         publish_runs.include?("--channel $env:PREFIX_CHANNEL")
    errors << "Prefix publication must upload the manifest-selected files to the canonical channel"
  end
  if publish_runs.include?("--force") || publish_runs.include?("--skip-existing")
    errors << "Prefix publication must fail on an existing immutable filename"
  end
  if contents.include?("PREFIX_API_KEY") || contents.match?(/secrets\./)
    errors << "Prefix publication must use Repository Access OIDC, not a stored API key"
  end
  unless publish_runs.include?("tools/test-windows-conda-consumer.ps1") &&
         publish_runs.include?("-ChannelUrl $env:PUBLIC_CHANNEL_URL") &&
         publish_runs.include?("-Attempts 6")
    errors << "Prefix publication must test clean consumers through the public channel"
  end
end

unless File.file?(staging_path)
  errors << "missing tools/prepare-windows-conda-release.ps1"
else
  staging = File.read(staging_path)
  {
    "structured package inspection" => "rattler-build package inspect",
    "runtime/development package set" => '@("orocos", "orocos-dev")',
    "exact runtime dependency" => '"orocos ==$version $($runtime.Metadata.index.build)"',
    "package path overlap check" => "HashSet[string]",
    "artifact checksums" => "Get-FileHash",
    "source lock in the release manifest" => "source_lock",
    "the win-64 target platform" => 'target_platform -cne "win-64"',
    "a full repository commit" => 'repository_commit -cnotmatch "^[0-9a-f]{40}$"',
    "local repodata verification" => "Test-LocalRepodata",
    "immutable checksum manifest" => "SHA256SUMS.txt"
  }.each do |contract, token|
    errors << "release staging must enforce #{contract}" unless staging.include?(token)
  end
  errors << "release staging must not publish packages" if staging.include?("upload prefix")
end

unless File.file?(consumer_path)
  errors << "missing tools/test-windows-conda-consumer.ps1"
else
  consumer = File.read(consumer_path)
  {
    "an exact runtime build" => '"orocos==$($runtime.version)=$($runtime.build)"',
    "an exact development build" => '"orocos-dev==$($development.version)=$($development.build)"',
    "a clean Pixi package cache" => "PIXI_CACHE_DIR",
    "the runtime activation contract" => "Library\\env.ps1",
    "the development activation contract" => "Library\\dev-env.ps1",
    "OroGen" => "orogen --version",
    "Typegen" => "typegen --help",
    "the OPC UA deployer" => "deployer-opcua-win32.exe --check --no-consolelog"
  }.each do |contract, token|
    errors << "consumer smoke test must check #{contract}" unless consumer.include?(token)
  end
end

if errors.any?
  warn errors.join("\n")
  exit 1
end
