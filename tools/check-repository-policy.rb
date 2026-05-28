#!/usr/bin/env ruby

root = File.expand_path("..", __dir__)
agents_path = File.join(root, "AGENTS.md")
readme_path = File.join(root, "README.md")
workflow_path = File.join(root, ".github", "workflows", "repository-policy.yml")
errors = []

required_policy_links = {
  "README.md" => "./README.md",
  "docs/src/architecture.md" => "./docs/src/architecture.md",
  "docs/src/package-policy.md" => "./docs/src/package-policy.md",
  "docs/src/install-contract.md" => "./docs/src/install-contract.md"
}.freeze

if !File.file?(agents_path)
  errors << "missing AGENTS.md"
else
  agents = File.read(agents_path)

  errors << "AGENTS.md: must describe the standalone Orocos/Rock toolchain contract" unless agents.include?("standalone Orocos/Rock toolchain")

  required_policy_links.each do |label, target|
    markdown_link = "[#{label}](#{target})"
    errors << "AGENTS.md: missing policy link #{markdown_link}" unless agents.include?(markdown_link)
  end

  %w[
    ./docs/architecture.md
    ./docs/package-policy.md
    ./docs/install-contract.md
  ].each do |stale_target|
    errors << "AGENTS.md: must not link stale path #{stale_target}" if agents.include?(stale_target)
  end
end

if !File.file?(readme_path)
  errors << "missing README.md"
else
  readme = File.read(readme_path)
  %w[
    ./docs/src/architecture.md
    ./docs/src/package-policy.md
    ./docs/src/install-contract.md
  ].each do |target|
    errors << "README.md: missing policy link #{target}" unless readme.include?(target)
  end
end

if !File.file?(workflow_path)
  errors << "missing .github/workflows/repository-policy.yml"
else
  workflow = File.read(workflow_path)

  errors << "repository policy workflow must run on pull requests" unless workflow.include?("pull_request:")
  errors << "repository policy workflow must run on pushes to main" unless workflow.include?("push:") && workflow.include?("- main")
  errors << "repository policy workflow must support manual dispatch" unless workflow.include?("workflow_dispatch:")
  %w[
    "AGENTS.md"
    "README.md"
    ".github/workflows/repository-policy.yml"
    "docs/src/**"
    "tools/check-repository-policy.rb"
  ].each do |path|
    errors << "repository policy workflow must watch #{path}" unless workflow.include?(path)
  end
  errors << "repository policy workflow must run repository policy check" unless workflow.include?("ruby tools/check-repository-policy.rb")
end

if errors.any?
  warn errors.join("\n")
  exit 1
end
