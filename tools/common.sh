#!/usr/bin/env bash

set -euo pipefail

OROCOS_ROCK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OROCOS_ROCK_DEFAULT_PREFIX="${OROCOS_PREFIX:-$HOME/.orocos}"

orocos_rock_die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

orocos_rock_info() {
    printf '%s\n' "$*" >&2
}

orocos_rock_require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        if [ "$1" = "autoproj" ]; then
            orocos_rock_die "required command 'autoproj' was not found in PATH; run ./tools/install-autoproj.sh or add an existing Autoproj install to PATH"
        fi
        orocos_rock_die "required command '$1' was not found in PATH"
    fi
}

orocos_rock_require_file() {
    [ -f "$1" ] || orocos_rock_die "required file is missing: $1"
}

orocos_rock_prepare_autoproj_workspace() {
    prefix="$1"
    osdeps_mode="${2:-none}"
    ruby_version="$(ruby -e 'print RUBY_VERSION')"
    ruby_executable="$(ruby -rrbconfig -e 'print RbConfig.ruby')"
    bundler_executable="$(ruby -e 'gem "bundler"; print Gem.bin_path("bundler", "bundle")')"
    mkdir -p "$OROCOS_ROCK_ROOT/.autoproj"
    mkdir -p "$OROCOS_ROCK_ROOT/.autoproj/bin"
    cat >"$OROCOS_ROCK_ROOT/.autoproj/bin/bundle" <<EOF
#! /bin/sh
exec "$ruby_executable" "$bundler_executable" "\$@"
EOF
    chmod +x "$OROCOS_ROCK_ROOT/.autoproj/bin/bundle"
    cp "$OROCOS_ROCK_ROOT/.autoproj/bin/bundle" "$OROCOS_ROCK_ROOT/.autoproj/bin/bundler"
    cat >"$OROCOS_ROCK_ROOT/.autoproj/Gemfile" <<EOF
source "https://rubygems.org"
ruby "$ruby_version" if respond_to?(:ruby)
gem "autoproj", ">= 2.18.0"
config_path = File.join(__dir__, 'config.yml')
if File.file?(config_path)
    require 'yaml'
    config = YAML.load(File.read(config_path)) || Hash.new
    (config['plugins'] || Hash.new).
        each do |plugin_name, (version, options)|
            gem plugin_name, version, **options
        end
end
EOF
    cat >"$OROCOS_ROCK_ROOT/.autoproj/config.yml" <<EOF
prefix: "$prefix"
gems_install_path: "$OROCOS_ROCK_ROOT/.autoproj/gems"
osdeps_mode: "$osdeps_mode"
apt_dpkg_update: false
prefer_indep_over_os_packages: false
USE_OCL: true
EOF
}

orocos_rock_require_autoproj() {
    orocos_rock_require_command ruby
    ruby -e 'gem "facets", "< 3.2"; gem "autoproj"; require "facets/kernel/constant"' >/dev/null 2>&1 ||
        orocos_rock_die "Autoproj Ruby gems are not usable; run ./tools/install-autoproj.sh"
}

orocos_rock_workspace_gem_home() {
    ruby -rrbconfig -e 'print File.join(ARGV.fetch(0), ".autoproj", "gems", "ruby", RbConfig::CONFIG.fetch("ruby_version"))' "$OROCOS_ROCK_ROOT"
}

orocos_rock_install_workspace_gem() {
    gem_name="$1"
    gem_version="${2:-}"
    workspace_gem_home="$3"

    cache_path="$(ruby -e 'name = ARGV.fetch(0); version = ARGV[1]; specs = Gem::Specification.find_all_by_name(name, version && !version.empty? ? "= #{version}" : nil); spec = specs.first; if spec; path = File.join(spec.cache_dir, "#{spec.full_name}.gem"); print path if File.file?(path); end' "$gem_name" "$gem_version")"
    downloaded_gem_path=""

    if [ -n "$gem_version" ]; then
        orocos_rock_info "Installing $gem_name $gem_version into workspace Ruby gems"
    else
        orocos_rock_info "Installing $gem_name into workspace Ruby gems"
    fi

    if [ -n "$cache_path" ]; then
        gem install --install-dir "$workspace_gem_home" --no-document "$cache_path"
    elif [ -n "$gem_version" ] && command -v curl >/dev/null 2>&1; then
        downloaded_gem_path="${TMPDIR:-/tmp}/$gem_name-$gem_version.gem"
        curl --fail --location --retry 5 --retry-delay 2 --retry-connrefused \
            --output "$downloaded_gem_path" "https://rubygems.org/downloads/$gem_name-$gem_version.gem"
        gem install --install-dir "$workspace_gem_home" --local --no-document "$downloaded_gem_path"
    elif [ -n "$gem_version" ]; then
        gem install --install-dir "$workspace_gem_home" --no-document "$gem_name" -v "$gem_version"
    else
        gem install --install-dir "$workspace_gem_home" --no-document "$gem_name"
    fi
}

orocos_rock_ensure_workspace_ruby_gems() {
    orocos_rock_require_command gem

    workspace_gem_home="$(orocos_rock_workspace_gem_home)"
    if GEM_HOME="$workspace_gem_home" GEM_PATH="" BUNDLE_GEMFILE="" \
        ruby -e 'gem "facets", "< 3.2"; require "facets/module/spacename"; gem "backports"; require "backports/2.4.0/true_class/dup"' >/dev/null 2>&1; then
        return 0
    fi

    mkdir -p "$workspace_gem_home"
    orocos_rock_install_workspace_gem facets 3.1.0 "$workspace_gem_home"
    orocos_rock_install_workspace_gem backports 3.25.3 "$workspace_gem_home"
}

orocos_rock_autoproj() {
    user_gem_home="$(ruby -rrubygems -e 'print Gem.user_dir')"
    gem_path="$(ruby -rrubygems -e 'print Gem.path.join(":")')"
    export XDG_DATA_HOME="${XDG_DATA_HOME:-$OROCOS_ROCK_ROOT/.autoproj/xdg}"
    export GEM_PATH="$gem_path"
    case ":$GEM_PATH:" in
        *:"$user_gem_home":*) ;;
        *) export GEM_PATH="$user_gem_home:$GEM_PATH" ;;
    esac
    ruby -e 'gem "facets", "< 3.2"; load Gem.bin_path("autoproj", "autoproj")' -- "$@"
}

orocos_rock_source_workspace_env() {
    if [ -f "$OROCOS_ROCK_ROOT/env.sh" ] &&
       [ -f "$OROCOS_ROCK_ROOT/.autoproj/env.sh" ] &&
       [ -f "$OROCOS_ROCK_ROOT/.bundle_env.sh" ]; then
        # shellcheck disable=SC1091
        . "$OROCOS_ROCK_ROOT/env.sh"
    fi
}
