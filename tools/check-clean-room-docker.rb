#!/usr/bin/env ruby

root = File.expand_path("..", __dir__)
private_reference_pattern = /meta[_-]?#{'nc'}/i

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
  errors << "Dockerfile must default to the standalone Ubuntu base image" unless contents.match?(/^ARG OROCOS_ROCK_BASE_IMAGE=ubuntu:24\.04$/)
  errors << "Dockerfile must build Orocos/Rock from the configurable standalone base image" unless contents.match?(/^FROM \$\{OROCOS_ROCK_BASE_IMAGE\} AS builder$/)
  errors << "Dockerfile final image must start again from the configurable standalone base image" unless contents.match?(/^FROM \$\{OROCOS_ROCK_BASE_IMAGE\} AS final$/)
  errors << "Dockerfile must not use private project images as an Orocos/Rock base" if contents.match?(private_reference_pattern)
  errors << "Dockerfile must not require an external Dockerfile frontend" if contents.match?(/^#\s*syntax=/)
  errors << "Dockerfile must switch to root after the base image" unless contents.include?("USER root")
  errors << "Dockerfile must clear inherited CMake toolchain settings for Orocos/Rock builds" unless contents.include?("ENV CMAKE_TOOLCHAIN_FILE=")
  errors << "Dockerfile must export SHELL=/bin/bash for Autoproj" unless contents.include?("ENV SHELL=/bin/bash")
  errors << "Dockerfile must install sudo for non-root Autoproj osdeps" unless contents.match?(/sudo\s+\\\n\s+xz-utils/) &&
                                                                             contents.match?(/ruby-dev\s+\\\n\s+sudo &&/)
  errors << "Dockerfile must create the non-root ubuntu user idempotently" unless contents.scan("if ! id -u ubuntu >/dev/null 2>&1").length == 2 &&
                                                                                     contents.scan("useradd --create-home --shell /bin/bash ubuntu").length == 2
  errors << "Dockerfile must ensure the ubuntu home directory is owned by ubuntu" unless contents.scan("chown ubuntu:ubuntu /home/ubuntu").length == 2
  errors << "Dockerfile must copy the workspace for the ubuntu user" unless contents.include?("COPY --chown=ubuntu:ubuntu . .")
  errors << "Dockerfile must make the install prefix writable by ubuntu" unless contents.include?('chown -R ubuntu:ubuntu /opt/orocos-rock "$OROCOS_PREFIX"')
  final_stage = contents.split(/^FROM \$\{OROCOS_ROCK_BASE_IMAGE\} AS final$/).last || ""
  errors << "Dockerfile final image must copy only the installed prefix from builder" unless final_stage.include?("COPY --from=builder --chown=ubuntu:ubuntu")
  errors << "Dockerfile final image must not copy or use the orocos-rock workspace" if final_stage.match?(/COPY .*\/opt\/orocos-rock/) || final_stage.include?("WORKDIR /opt/orocos-rock")
  errors << "Dockerfile final image must assert the orocos-rock workspace is absent" unless final_stage.include?("test ! -e /opt/orocos-rock")
  errors << "Dockerfile final image must assert Autoproj is absent" unless final_stage.include?("! command -v autoproj")
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
  expected_cmd = 'CMD ["bash", "-lc", "source \"$OROCOS_PREFIX/dev-env.sh\" && exec bash"]'
  errors << "Dockerfile CMD must source dev-env.sh through OROCOS_PREFIX" unless contents.include?(expected_cmd)
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
  errors << "workflow must tag the standalone local image" unless contents.include?("orocos-rock:latest")
  errors << "workflow must not reference private project names" if contents.match?(private_reference_pattern)
  smoke_test_index = contents.index("docker run --rm --user ubuntu")
  smoke_test_block = smoke_test_index ? contents[smoke_test_index, 600] : ""
  errors << "workflow must run the smoke test container as ubuntu" unless smoke_test_index
  errors << "workflow smoke test must fail on any failed assertion" unless smoke_test_block.include?("set -euo pipefail")
  errors << "workflow must smoke-test deployer-gnulinux" unless contents.include?("command -v deployer-gnulinux")
  errors << "workflow must smoke-test orogen" unless contents.include?("command -v orogen")
  errors << "workflow must smoke-test typegen" unless contents.include?("command -v typegen")
  errors << "workflow must assert Autoproj is absent from the final image" unless contents.include?("! command -v autoproj")
  errors << "workflow must assert the orocos-rock workspace is absent from the final image" unless contents.include?("test ! -e /opt/orocos-rock")
end

docker_build = File.join(root, "tools/docker-build.sh")
if File.file?(docker_build)
  contents = File.read(docker_build)
  errors << "docker-build.sh must default to the standalone local image tag" unless contents.include?("orocos-rock:latest")
  errors << "docker-build.sh must not reference private project names" if contents.match?(private_reference_pattern)
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
