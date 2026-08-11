#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/common.sh"

test_root="$(mktemp -d "${TMPDIR:-/tmp}/orocos-rock-autoproj-launcher.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

OROCOS_ROCK_ROOT="$test_root"
orocos_rock_require_autoproj
orocos_rock_prepare_autoproj_workspace "$test_root/prefix" none gnulinux

launcher="$test_root/.autoproj/bin/autoproj"
[ -x "$launcher" ] || orocos_rock_die "generated Autoproj launcher is missing or not executable: $launcher"

version_output="$(
    cd "$test_root"
    ruby "$launcher" version
)"
autoproj_version="$(sed -nE 's/^autoproj version: ([^[:space:]]+)$/\1/p' <<<"$version_output")"
[ -n "$autoproj_version" ] ||
    orocos_rock_die "generated Autoproj launcher returned an unexpected version: $version_output"
ruby -rrubygems -e 'exit(Gem::Version.new(ARGV.fetch(0)) >= Gem::Version.new(ARGV.fetch(1)) ? 0 : 1)' \
    "$autoproj_version" 2.18.0 ||
    orocos_rock_die "generated Autoproj launcher version is below 2.18.0: $autoproj_version"
