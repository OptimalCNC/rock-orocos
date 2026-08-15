#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/common.sh"

test_root="$(mktemp -d "${TMPDIR:-/tmp}/orocos-rock-install-env-test.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

export TMPDIR="$test_root/tmp"
mkdir -p "$TMPDIR"

overwrite_install_env() {
    local prefix="$1"
    local status="$2"

    mkdir -p "$prefix"
    printf '%s\n' 'source "/tmp/disposable-workspace/env.sh"' >"$prefix/env.sh"
    printf '%s\n' 'source "/tmp/disposable-workspace/dev-env.sh"' >"$prefix/dev-env.sh"
    return "$status"
}

record_unexpected_execution() {
    : >"$test_root/command-ran"
}

assert_snapshot_directory_is_empty() {
    if find "$TMPDIR" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
        orocos_rock_die "installed environment snapshot was not cleaned up"
    fi
}

prefix="$test_root/prefix with spaces"
mkdir -p "$prefix"
printf '%s\n' 'OROCOS_PREFIX_STABLE=runtime' >"$prefix/env.sh"
printf '%s\n' 'OROCOS_PREFIX_STABLE=development' >"$prefix/dev-env.sh"
chmod 751 "$prefix/env.sh"
chmod 750 "$prefix/dev-env.sh"
cp -a "$prefix/env.sh" "$test_root/expected-env.sh"
cp -a "$prefix/dev-env.sh" "$test_root/expected-dev-env.sh"

orocos_rock_run_preserving_install_env "$prefix" overwrite_install_env "$prefix" 0
cmp -s "$test_root/expected-env.sh" "$prefix/env.sh" ||
    orocos_rock_die "successful Autoproj operation replaced installed env.sh"
cmp -s "$test_root/expected-dev-env.sh" "$prefix/dev-env.sh" ||
    orocos_rock_die "successful Autoproj operation replaced installed dev-env.sh"
[ "$(stat -c '%a' "$prefix/env.sh")" = 751 ] ||
    orocos_rock_die "env.sh mode was not restored"
[ "$(stat -c '%a' "$prefix/dev-env.sh")" = 750 ] ||
    orocos_rock_die "dev-env.sh mode was not restored"
assert_snapshot_directory_is_empty

if orocos_rock_run_preserving_install_env "$prefix" overwrite_install_env "$prefix" 37; then
    orocos_rock_die "failing Autoproj fixture unexpectedly succeeded"
else
    operation_status=$?
fi
[ "$operation_status" -eq 37 ] ||
    orocos_rock_die "Autoproj failure status was not preserved: $operation_status"
cmp -s "$test_root/expected-env.sh" "$prefix/env.sh" ||
    orocos_rock_die "failed Autoproj operation replaced installed env.sh"
cmp -s "$test_root/expected-dev-env.sh" "$prefix/dev-env.sh" ||
    orocos_rock_die "failed Autoproj operation replaced installed dev-env.sh"
assert_snapshot_directory_is_empty

fresh_prefix="$test_root/fresh-prefix"
if orocos_rock_run_preserving_install_env "$fresh_prefix" \
    overwrite_install_env "$fresh_prefix" 23; then
    orocos_rock_die "fresh-prefix failure fixture unexpectedly succeeded"
else
    operation_status=$?
fi
[ "$operation_status" -eq 23 ] ||
    orocos_rock_die "fresh-prefix failure status was not preserved: $operation_status"
[ ! -e "$fresh_prefix/env.sh" ] ||
    orocos_rock_die "transient env.sh remained in a fresh install prefix"
[ ! -e "$fresh_prefix/dev-env.sh" ] ||
    orocos_rock_die "transient dev-env.sh remained in a fresh install prefix"
assert_snapshot_directory_is_empty

invalid_prefix="$test_root/invalid-prefix"
mkdir -p "$invalid_prefix/env.sh"
if orocos_rock_run_preserving_install_env "$invalid_prefix" \
    record_unexpected_execution; then
    orocos_rock_die "directory-valued installed environment entry was accepted"
fi
[ ! -e "$test_root/command-ran" ] ||
    orocos_rock_die "operation ran without a valid installed environment snapshot"
[ -d "$invalid_prefix/env.sh" ] ||
    orocos_rock_die "invalid installed environment entry was modified"
assert_snapshot_directory_is_empty
