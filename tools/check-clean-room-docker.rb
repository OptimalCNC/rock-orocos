#!/usr/bin/env ruby

root = File.expand_path("..", __dir__)

required_files = [
  ".dockerignore",
  ".github/workflows/clean-room-docker.yml",
  "docker/orocos-rock/Dockerfile",
  "tools/docker-build.sh",
  "tools/validate-install.sh"
]

errors = []

required_files.each do |relative|
  path = File.join(root, relative)
  errors << "missing #{relative}" unless File.file?(path)
end

install_autoproj = File.join(root, "tools/install-autoproj.sh")
if File.file?(install_autoproj)
  contents = File.read(install_autoproj)
  errors << "install-autoproj.sh must download exact facets gem artifacts directly" unless contents.include?("downloads/facets-3.1.0.gem")
  errors << "install-autoproj.sh must retry network gem downloads" unless contents.include?("--retry")
  errors << "install-autoproj.sh must retry Autoproj gem installation" unless contents.include?("orocos_rock_retry") && contents.include?("gem install --user-install --conservative")
end

dockerfile = File.join(root, "docker/orocos-rock/Dockerfile")
if File.file?(dockerfile)
  contents = File.read(dockerfile)
  errors << "Dockerfile must start from ubuntu:24.04" unless contents.match?(/^FROM ubuntu:24\.04$/)
  errors << "Dockerfile must not require an external Dockerfile frontend" if contents.match?(/^#\s*syntax=/)
  errors << "Dockerfile must export SHELL=/bin/bash for Autoproj" unless contents.include?("ENV SHELL=/bin/bash")
  shell_index = contents.index("SHELL [\"/bin/bash\", \"-lc\"]")
  bootstrap_index = contents.index("RUN ./tools/bootstrap.sh")
  if shell_index.nil?
    errors << "Dockerfile must switch Docker RUN steps to bash"
  elsif bootstrap_index && shell_index > bootstrap_index
    errors << "Dockerfile must switch to bash before running bootstrap/install wrapper scripts"
  end
  errors << "Dockerfile must run tools/bootstrap.sh" unless contents.include?("./tools/bootstrap.sh")
  errors << "Dockerfile must run tools/install.sh" unless contents.include?("./tools/install.sh")
  errors << "Dockerfile must run tools/validate-install.sh" unless contents.include?("./tools/validate-install.sh")
  expected_cmd = 'CMD ["bash", "-lc", "source \"$OROCOS_ROCK_PREFIX/dev-env.sh\" && exec bash"]'
  errors << "Dockerfile CMD must source dev-env.sh through OROCOS_ROCK_PREFIX" unless contents.include?(expected_cmd)
end

workflow = File.join(root, ".github/workflows/clean-room-docker.yml")
if File.file?(workflow)
  contents = File.read(workflow)
  errors << "workflow must build docker/orocos-rock/Dockerfile" unless contents.include?("docker/orocos-rock/Dockerfile")
  errors << "workflow must avoid pushing images" unless contents.include?("push: false")
end

common = File.join(root, "tools/common.sh")
if File.file?(common)
  contents = File.read(common)
  errors << "common.sh must pin workspace backports gem" unless contents.include?("backports 3.25.3")
  errors << "common.sh must support direct RubyGems artifact downloads" unless contents.include?("rubygems.org/downloads")
end

if errors.any?
  warn errors.join("\n")
  exit 1
end
