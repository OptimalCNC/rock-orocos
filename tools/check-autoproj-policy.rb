#!/usr/bin/env ruby

require "yaml"

root = File.expand_path("..", __dir__)
overrides_path = File.join(root, "autoproj", "overrides.yml")
local_autobuild_path = File.join(root, "autoproj", "local.autobuild")
install_path = File.join(root, "tools", "install.sh")
install_autoproj_path = File.join(root, "tools", "install-autoproj.sh")
setup_path = File.join(root, "tools", "setup.sh")
rtt_manifest_path = File.join(root, "autoproj", "manifests", "rtt.xml")
local_osdeps_path = File.join(root, "autoproj", "orocos-rock.osdeps")
export_env_path = File.join(root, "tools", "export-env.sh")
validate_install_path = File.join(root, "tools", "validate-install.sh")
ruby_tools_path = File.join(root, "tools", "install-ruby-tools.sh")
common_path = File.join(root, "tools", "common.sh")
native_ci_check_path = File.join(root, "tools", "check-native-ci.rb")
package_tests_ci_check_path = File.join(root, "tools", "check-package-tests-ci.rb")
cpp17_policy_check_path = File.join(root, "tools", "check-cpp17-policy.rb")
rtlog_prefix_check_path = File.join(root, "tools", "check-rtlog-prefix.sh")

expected_forks = {
  "farbot" => { "url" => "https://github.com/liufang-robot/farbot.git", "branch" => "dev" },
  "rtlog-cpp" => { "url" => "https://github.com/liufang-robot/rtlog-cpp.git", "branch" => "dev" },
  "rtt" => { "url" => "https://github.com/liufang-robot/rtt.git", "branch" => "codex/rtlog-backend" },
  "ocl" => { "url" => "https://github.com/OptimalCNC/ocl.git", "branch" => "dev" },
  "log4cpp" => { "url" => "https://github.com/OptimalCNC/log4cpp.git", "branch" => "dev" },
  "orogen" => { "url" => "https://github.com/OptimalCNC/tools-orogen.git", "branch" => "dev" },
  "typelib" => { "url" => "https://github.com/OptimalCNC/tools-typelib.git", "branch" => "dev" },
  "utilmm" => { "url" => "https://github.com/OptimalCNC/utilmm.git", "branch" => "dev" },
  "rtt_typelib" => { "url" => "https://github.com/OptimalCNC/tools-rtt_typelib.git", "branch" => "dev" },
  "stdint_typekit" => { "url" => "https://github.com/OptimalCNC/stdint_typekit.git", "branch" => "dev" }
}

source_selection = YAML.safe_load_file(overrides_path)
version_control = source_selection.fetch("version_control", [])
overrides = source_selection.fetch("overrides", [])
errors = []

expected_forks.each do |package, source|
  source_entries = %w[farbot rtlog-cpp].include?(package) ? version_control : overrides
  override = source_entries.find { |entry| entry.key?(package) }

  if override.nil?
    errors << "#{package}: missing source selection"
    next
  end

  actual_url = override["url"]
  actual_branch = override["branch"]

  errors << "#{package}: expected url #{source.fetch("url")}, got #{actual_url.inspect}" unless actual_url == source.fetch("url")
  errors << "#{package}: expected branch #{source.fetch("branch")}, got #{actual_branch.inspect}" unless actual_branch == source.fetch("branch")
end

install_script = File.read(install_path)
install_autoproj_script = File.read(install_autoproj_path)
setup_script = File.file?(setup_path) ? File.read(setup_path) : nil
common_script = File.read(common_path)
overrides_script = File.read(File.join(root, "autoproj", "overrides.rb"))
local_autobuild_script = File.file?(local_autobuild_path) ? File.read(local_autobuild_path) : ""
local_osdeps = File.file?(local_osdeps_path) ? File.read(local_osdeps_path) : ""
local_osdeps_data = local_osdeps.empty? ? {} : (YAML.safe_load(local_osdeps) || {})
export_env_script = File.read(export_env_path)
validate_install_script = File.read(validate_install_path)

expected_forks.each_key do |package|
  refreshes_package = install_script.include?("FORKED_PACKAGES=(") &&
                      install_script.match?(/FORKED_PACKAGES=\([^)]*\b#{Regexp.escape(package)}\b[^)]*\)/m)
  errors << "install.sh: must refresh maintained fork #{package}" unless refreshes_package
end

unless local_autobuild_script.include?('cmake_package "farbot"')
  errors << "autoproj/local.autobuild: must define farbot as a local CMake package"
end

unless local_autobuild_script.include?('cmake_package "rtlog-cpp"') &&
       local_autobuild_script.include?('pkg.depends_on "farbot"')
  errors << "autoproj/local.autobuild: must define rtlog-cpp as a local CMake package depending on farbot"
end

unless install_script.match?(/FORKED_PACKAGES=\([^)]*\bfarbot\b[^)]*\brtlog-cpp\b[^)]*\brtt\b[^)]*\)/m)
  errors << "install.sh: farbot and rtlog-cpp must be refreshed before rtt"
end

source_update = install_script.index("orocos_rock_autoproj update")
osdeps = install_script.index("orocos_rock_autoproj osdeps")
build = install_script.index("orocos_rock_autoproj build")

if source_update.nil?
  errors << "install.sh: missing Autoproj source update before build"
elsif build && source_update > build
  errors << "install.sh: Autoproj source update must run before build"
end

cpp17_check = install_script.index('ruby "$SCRIPT_DIR/check-cpp17-policy.rb"')
if cpp17_check.nil?
  errors << "install.sh: missing C++17 package policy check after source update"
elsif source_update && cpp17_check < source_update
  errors << "install.sh: C++17 package policy check must run after Autoproj source update"
elsif build && cpp17_check > build
  errors << "install.sh: C++17 package policy check must run before build"
end

if osdeps.nil?
  errors << "install.sh: missing Autoproj osdeps refresh after source update"
elsif source_update && osdeps < source_update
  errors << "install.sh: Autoproj osdeps refresh must happen after source update"
elsif build && osdeps > build
  errors << "install.sh: Autoproj osdeps refresh must happen before build"
end

unless overrides_script.match?(/setup_package\s+["']rtt["']/) &&
       overrides_script.include?("use_package_xml = true")
  errors << "autoproj/overrides.rb: rtt must opt into package.xml manifest loading"
end

unless overrides_script.match?(/setup_package\s+["']rtt["']/) &&
       overrides_script.include?('pkg.depends_on "rtlog-cpp"')
  errors << "autoproj/overrides.rb: rtt must depend on rtlog-cpp for the bounded logger backend"
end

unless export_env_script.include?('OROCOS_PREFIX="$PREFIX"') &&
       export_env_script.include?("export OROCOS_PREFIX")
  errors << "tools/export-env.sh: env.sh must bind OROCOS_PREFIX to the generated install prefix"
end

unless common_script.include?("orocos_rock_validate_target") &&
       common_script.include?("gnulinux|xenomai") &&
       common_script.include?('rtt_target: "$target"')
  errors << "tools/common.sh: must validate gnulinux/xenomai targets and persist rtt_target in Autoproj config"
end

unless install_script.include?("--target TARGET") &&
       install_script.include?('"$SCRIPT_DIR/export-env.sh" --prefix "$PREFIX" --target "$TARGET"')
  errors << "tools/install.sh: must accept --target and pass it to export-env.sh"
end

unless export_env_script.include?("--target TARGET") &&
       export_env_script.include?('OROCOS_TARGET="$TARGET"')
  errors << "tools/export-env.sh: env.sh must export the selected Orocos target"
end

if export_env_script.include?('${OROCOS_ROCK_PREFIX:-')
  errors << "tools/export-env.sh: generated env.sh must not redirect through OROCOS_ROCK_PREFIX"
end

unless export_env_script.include?('PATH "\$OROCOS_PREFIX/toolchain/bin"')
  errors << "tools/export-env.sh: env.sh must prepend the installed toolchain bin directory"
end

unless export_env_script.include?('CMAKE_PREFIX_PATH "\$OROCOS_PREFIX/toolchain"')
  errors << "tools/export-env.sh: env.sh must prepend the installed toolchain prefix"
end

root_lib = export_env_script.index('LD_LIBRARY_PATH "\$OROCOS_PREFIX/lib"')
toolchain_lib = export_env_script.index('LD_LIBRARY_PATH "\$OROCOS_PREFIX/toolchain/lib"')
if root_lib && toolchain_lib && root_lib > toolchain_lib
  errors << "tools/export-env.sh: toolchain libraries must take precedence over root prefix libraries"
end

root_pkg_config = export_env_script.index('PKG_CONFIG_PATH "\$OROCOS_PREFIX/lib/pkgconfig"')
toolchain_pkg_config = export_env_script.index('PKG_CONFIG_PATH "\$OROCOS_PREFIX/toolchain/lib/pkgconfig"')
if root_pkg_config && toolchain_pkg_config && root_pkg_config > toolchain_pkg_config
  errors << "tools/export-env.sh: toolchain pkg-config metadata must take precedence over root prefix metadata"
end

unless export_env_script.include?('GEM_HOME="\${GEM_HOME:-') &&
       export_env_script.include?('toolchain/gems')
  errors << "tools/export-env.sh: dev-env.sh must activate the installed Ruby gem home"
end

unless validate_install_script.include?('DEPLOYER="$(orocos_rock_target_deployer "$TARGET")"') &&
       validate_install_script.include?("orocos_rock_validate_deployer_version_output")
  errors << "tools/validate-install.sh: must smoke-test the selected target deployer"
end

unless common_script.include?("orocos_rock_validate_deployer_version_output") &&
       common_script.include?("OROCOS Toolchain version") &&
       common_script.include?("Xenomai/cobalt")
  errors << "tools/common.sh: must validate deployer version output for gnulinux and xenomai"
end

unless validate_install_script.include?("orogen --help")
  errors << "tools/validate-install.sh: must smoke-test orogen"
end

unless validate_install_script.include?("typegen --help")
  errors << "tools/validate-install.sh: must smoke-test typegen"
end

unless File.file?(ruby_tools_path)
  errors << "tools/install-ruby-tools.sh: missing Ruby tool staging script"
else
  ruby_tools_script = File.read(ruby_tools_path)
  errors << "tools/install-ruby-tools.sh: must stage utilrb" unless ruby_tools_script.include?("toolchain/tools/utilrb")
  errors << "tools/install-ruby-tools.sh: must stage metaruby" unless ruby_tools_script.include?("tools/metaruby")
  errors << "tools/install-ruby-tools.sh: must stage orogen" unless ruby_tools_script.include?("toolchain/tools/orogen")
end

errors << "tools/check-native-ci.rb: missing native CI policy check" unless File.file?(native_ci_check_path)
errors << "tools/check-package-tests-ci.rb: missing package test CI policy check" unless File.file?(package_tests_ci_check_path)
errors << "tools/check-cpp17-policy.rb: missing C++17 policy check" unless File.file?(cpp17_policy_check_path)
errors << "tools/check-rtlog-prefix.sh: missing rtlog installed-prefix smoke test" unless File.file?(rtlog_prefix_check_path)

unless install_script.include?('"$SCRIPT_DIR/install-ruby-tools.sh" --prefix "$PREFIX"')
  errors << "install.sh: must stage Ruby generator tools into the install prefix"
end

if setup_script.nil?
  errors << "tools/setup.sh: missing user-facing setup wrapper"
else
  expected_setup_steps = [
    '"$SCRIPT_DIR/install-autoproj.sh"',
    '"$SCRIPT_DIR/bootstrap.sh" --prefix "$PREFIX" --target "$TARGET"',
    '"$SCRIPT_DIR/install.sh" --prefix "$PREFIX" --target "$TARGET"',
    '"$SCRIPT_DIR/validate-install.sh" --prefix "$PREFIX" --target "$TARGET"'
  ]
  expected_setup_steps.each do |step|
    errors << "tools/setup.sh: missing setup step #{step}" unless setup_script.include?(step)
  end
end

unless common_script.include?('.autoproj/Gemfile') &&
       common_script.include?('gem "autoproj", ">= 2.18.0"')
  errors << "tools/common.sh: must create .autoproj/Gemfile for Autoproj bundler osdeps"
end

unless common_script.include?('BUNDLE_GEMFILE="${BUNDLE_GEMFILE:-$OROCOS_ROCK_ROOT/.autoproj/Gemfile}"')
  errors << "tools/common.sh: must provide BUNDLE_GEMFILE while invoking Autoproj"
end

unless common_script.include?('orocos_rock_user_gem_home') &&
       common_script.include?('GEM_PATH="$user_gem_home${GEM_PATH:+:$GEM_PATH}"')
  errors << "tools/common.sh: must include RubyGems user install directory when loading Autoproj"
end

unless install_autoproj_script.include?('GEM_PATH="$USER_GEM_HOME${GEM_PATH:+:$GEM_PATH}"')
  errors << "tools/install-autoproj.sh: must include RubyGems user install directory when validating Autoproj"
end

unless common_script.include?('.autoproj/bin/bundle') &&
       common_script.include?('Gem.bin_path("bundler", "bundle")')
  errors << "tools/common.sh: must seed .autoproj/bin/bundle before Autoproj osdeps"
end

if !File.file?(rtt_manifest_path)
  errors << "autoproj/manifests/rtt.xml: missing tracked manifest for bootstrap-time RTT osdeps"
else
  rtt_manifest = File.read(rtt_manifest_path)
  errors << "autoproj/manifests/rtt.xml: must declare boost as a package dependency" unless rtt_manifest.include?('<depend package="boost" />')
  errors << "autoproj/manifests/rtt.xml: must declare omniorb as a package dependency" unless rtt_manifest.include?('<depend package="omniorb" />')
  errors << "autoproj/manifests/rtt.xml: must declare xpath-perl as a package dependency" unless rtt_manifest.include?('<depend package="xpath-perl" />')
end

if local_osdeps_data.key?("ruby")
  errors << "autoproj/orocos-rock.osdeps: must not override ruby directly; Autoproj aliases ruby to the active rubyXX osdep"
end

%w[ruby33 ruby34].each do |ruby_osdep|
  unless local_osdeps_data.dig(ruby_osdep, "debian,ubuntu") == "ruby"
    errors << "autoproj/orocos-rock.osdeps: must define #{ruby_osdep} for Debian/Ubuntu package-set compatibility"
  end
end

unless local_osdeps_data.dig("ruby-dev", "debian,ubuntu") == "ruby-dev"
  errors << "autoproj/orocos-rock.osdeps: must define ruby-dev for Debian/Ubuntu package-set compatibility"
end

unless local_osdeps_data.dig("omniorb", "debian,ubuntu") == ["omniidl", "libomniorb4-dev"]
  errors << "autoproj/orocos-rock.osdeps: must override omniorb without unavailable omniorb-nameserver on Debian/Ubuntu"
end

%w[ncurses libncurses libncurses-dev].each do |ncurses_osdep|
  unless local_osdeps_data.dig(ncurses_osdep, "debian,ubuntu") == "libncurses-dev"
    errors << "autoproj/orocos-rock.osdeps: must map #{ncurses_osdep} to libncurses-dev on Debian/Ubuntu"
  end
end

if errors.any?
  warn errors.join("\n")
  exit 1
end
