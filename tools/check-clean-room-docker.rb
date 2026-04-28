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
  errors << "Dockerfile must start from MetaNC shared image" unless contents.match?(/^FROM optimalcnc\/metanc:latest$/)
  errors << "Dockerfile must not require an external Dockerfile frontend" if contents.match?(/^#\s*syntax=/)
  errors << "Dockerfile must switch to root after the MetaNC base image" unless contents.include?("USER root")
  errors << "Dockerfile must clear MetaNC vcpkg CMake toolchain for Orocos/Rock builds" unless contents.include?("ENV CMAKE_TOOLCHAIN_FILE=")
  errors << "Dockerfile must export SHELL=/bin/bash for Autoproj" unless contents.include?("ENV SHELL=/bin/bash")
  errors << "Dockerfile must copy the workspace for the ubuntu user" unless contents.include?("COPY --chown=ubuntu:ubuntu . .")
  errors << "Dockerfile must make the install prefix writable by ubuntu" unless contents.include?('chown -R ubuntu:ubuntu /opt/orocos-rock "$OROCOS_ROCK_PREFIX"')
  user_ubuntu_index = contents.index("USER ubuntu")
  install_autoproj_index = contents.index("RUN ./tools/install-autoproj.sh")
  if user_ubuntu_index.nil?
    errors << "Dockerfile must switch to ubuntu before running wrapper scripts"
  elsif install_autoproj_index && user_ubuntu_index > install_autoproj_index
    errors << "Dockerfile must run wrapper scripts as ubuntu"
  end
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
  errors << "workflow must use the Blacksmith x64 runner for Docker builds" unless contents.include?("runs-on: blacksmith-4vcpu-ubuntu-2404")
  errors << "workflow must use Blacksmith Docker builder setup" unless contents.include?("useblacksmith/setup-docker-builder@v1")
  errors << "workflow must use Blacksmith build-push action" unless contents.include?("useblacksmith/build-push-action@v2")
  errors << "workflow must pull the latest base image during Docker builds" unless contents.include?("pull: true")
  errors << "workflow must load the built image for smoke testing" unless contents.include?("load: true")
  errors << "workflow must build docker/orocos-rock/Dockerfile" unless contents.include?("docker/orocos-rock/Dockerfile")
  errors << "workflow must avoid pushing images" unless contents.include?("push: false")
  errors << "workflow must tag the MetaNC-based local image" unless contents.include?("orocos-rock:metanc-latest")
  errors << "workflow must run the smoke test container as ubuntu" unless contents.include?("docker run --rm --user ubuntu")
  errors << "workflow must smoke-test deployer-gnulinux" unless contents.include?("command -v deployer-gnulinux")
  errors << "workflow must smoke-test orogen" unless contents.include?("command -v orogen")
  errors << "workflow must smoke-test typegen" unless contents.include?("command -v typegen")
end

docker_build = File.join(root, "tools/docker-build.sh")
if File.file?(docker_build)
  contents = File.read(docker_build)
  errors << "docker-build.sh must default to the MetaNC-based local image tag" unless contents.include?("orocos-rock:metanc-latest")
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
