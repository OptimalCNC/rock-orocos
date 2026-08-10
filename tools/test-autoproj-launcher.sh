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

version_output="$(ruby "$launcher" version)"
grep -Eq '^autoproj version: 2\.18\.' <<<"$version_output" ||
    orocos_rock_die "generated Autoproj launcher returned an unexpected version: $version_output"
