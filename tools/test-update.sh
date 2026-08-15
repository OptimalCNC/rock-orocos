#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBJECT="$SCRIPT_DIR/update.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_contains() {
    haystack="$1"
    needle="$2"
    case "$haystack" in
        *"$needle"*) ;;
        *) fail "expected output to contain: $needle" ;;
    esac
}

assert_not_contains() {
    haystack="$1"
    needle="$2"
    case "$haystack" in
        *"$needle"*) fail "expected output not to contain: $needle" ;;
        *) ;;
    esac
}

test_root="$(mktemp -d "${TMPDIR:-/tmp}/orocos-rock-update.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

create_fixture() {
    fixture_name="$1"
    fixture_root="$test_root/$fixture_name"
    fixture_source="$fixture_root/source"
    fixture_remote="$fixture_root/remote.git"
    fixture_checkout="$fixture_root/checkout"
    fixture_trace="$fixture_root/trace.log"

    mkdir -p "$fixture_source/tools" "$fixture_source/autoproj"
    cp "$SUBJECT" "$fixture_source/tools/update.sh"
    chmod +x "$fixture_source/tools/update.sh"
    touch "$fixture_source/autoproj/manifest"

    cat >"$fixture_source/tools/common.sh" <<'EOF'
#!/usr/bin/env bash

OROCOS_ROCK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OROCOS_ROCK_DEFAULT_PREFIX="${OROCOS_PREFIX:-$HOME/.orocos}"
OROCOS_ROCK_DEFAULT_TARGET="${OROCOS_TARGET:-gnulinux}"

printf 'common:%s\n' "${OROCOS_ROCK_UPDATE_REEXEC_HEAD:-unset}" >>"$UPDATE_TEST_TRACE"

orocos_rock_die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

orocos_rock_info() {
    printf '%s\n' "$*" >&2
}

orocos_rock_require_command() {
    command -v "$1" >/dev/null 2>&1 || orocos_rock_die "missing command: $1"
}

orocos_rock_require_file() {
    [ -f "$1" ] || orocos_rock_die "missing file: $1"
}

orocos_rock_validate_target() {
    case "$1" in
        gnulinux|xenomai) ;;
        *) orocos_rock_die "unsupported Orocos target '$1'; expected gnulinux or xenomai" ;;
    esac
}

orocos_rock_require_autoproj() { :; }
orocos_rock_ensure_workspace_ruby_gems() { :; }
orocos_rock_source_workspace_env() { :; }

orocos_rock_configure_target_environment() {
    orocos_rock_validate_target "$1"
    export OROCOS_TARGET="$1"
}

orocos_rock_prepare_autoproj_workspace() {
    printf 'prepare:%s:%s:%s\n' "$1" "$2" "$3" >>"$UPDATE_TEST_TRACE"
}

orocos_rock_autoproj() {
    printf 'autoproj' >>"$UPDATE_TEST_TRACE"
    for argument in "$@"; do
        printf ' <%s>' "$argument" >>"$UPDATE_TEST_TRACE"
    done
    printf '\n' >>"$UPDATE_TEST_TRACE"
    return "${UPDATE_TEST_AUTOPROJ_STATUS:-0}"
}
EOF

    git init -q -b main "$fixture_source"
    git -C "$fixture_source" config user.name "Update Test"
    git -C "$fixture_source" config user.email "update-test@example.invalid"
    git -C "$fixture_source" add tools/update.sh tools/common.sh autoproj/manifest
    git -C "$fixture_source" commit -q -m "initial fixture"
    git clone -q --bare "$fixture_source" "$fixture_remote"
    git -C "$fixture_source" remote add origin "$fixture_remote"
    git clone -q "$fixture_remote" "$fixture_checkout"
    git -C "$fixture_checkout" config user.name "Update Test"
    git -C "$fixture_checkout" config user.email "update-test@example.invalid"
}

[ -x "$SUBJECT" ] || fail "missing executable subject: $SUBJECT"

help_output="$($SUBJECT --help)"
assert_contains "$help_output" "Usage: ./tools/update.sh"

if invalid_output="$($SUBJECT --invalid 2>&1)"; then
    fail "unknown argument unexpectedly succeeded"
fi
assert_contains "$invalid_output" "unknown argument: --invalid"

if prefix_output="$($SUBJECT --prefix 2>&1)"; then
    fail "missing --prefix value unexpectedly succeeded"
fi
assert_contains "$prefix_output" "--prefix requires a value"

if target_value_output="$($SUBJECT --target 2>&1)"; then
    fail "missing --target value unexpectedly succeeded"
fi
assert_contains "$target_value_output" "--target requires a value"

if target_output="$($SUBJECT --target invalid 2>&1)"; then
    fail "unsupported target unexpectedly succeeded"
fi
assert_contains "$target_output" "unsupported Orocos target 'invalid'"

create_fixture success
printf 'updated\n' >"$fixture_source/root-version.txt"
git -C "$fixture_source" add root-version.txt
git -C "$fixture_source" commit -q -m "advance fixture root"
git -C "$fixture_source" push -q origin main
expected_head="$(git -C "$fixture_source" rev-parse HEAD)"

UPDATE_TEST_TRACE="$fixture_trace" \
    "$fixture_checkout/tools/update.sh" \
    --prefix "$fixture_root/prefix" \
    --target gnulinux >"$fixture_root/output.log" 2>&1

[ "$(git -C "$fixture_checkout" rev-parse HEAD)" = "$expected_head" ] ||
    fail "root checkout did not fast-forward"
[ "$(grep -c '^common:' "$fixture_trace")" -eq 2 ] ||
    fail "updated command was not executed exactly twice"
[ "$(grep -c '^prepare:' "$fixture_trace")" -eq 1 ] ||
    fail "workspace was not prepared exactly once"
[ "$(grep -c '^autoproj' "$fixture_trace")" -eq 1 ] ||
    fail "Autoproj was not invoked exactly once"
success_trace="$(cat "$fixture_trace")"
assert_contains "$success_trace" "common:unset"
assert_contains "$success_trace" "common:$expected_head"
assert_contains "$success_trace" "prepare:$fixture_root/prefix:none:gnulinux"
assert_contains "$success_trace" "autoproj <update> <--no-interactive> <--no-osdeps> <--no-config> <--no-bundler> <--no-autoproj>"
assert_not_contains "$success_trace" "reset"
assert_not_contains "$success_trace" "build"

create_fixture dirty
printf 'dirty\n' >>"$fixture_checkout/autoproj/manifest"
if dirty_output="$(UPDATE_TEST_TRACE="$fixture_trace" "$fixture_checkout/tools/update.sh" 2>&1)"; then
    fail "dirty root unexpectedly updated"
fi
assert_contains "$dirty_output" "root worktree has local changes"
assert_not_contains "$(cat "$fixture_trace")" "autoproj"

create_fixture no-upstream
git -C "$fixture_checkout" branch --unset-upstream
if upstream_output="$(UPDATE_TEST_TRACE="$fixture_trace" "$fixture_checkout/tools/update.sh" 2>&1)"; then
    fail "branch without upstream unexpectedly updated"
fi
assert_contains "$upstream_output" "has no configured upstream"
assert_not_contains "$(cat "$fixture_trace")" "autoproj"

create_fixture divergent
printf 'remote\n' >"$fixture_source/remote-version.txt"
git -C "$fixture_source" add remote-version.txt
git -C "$fixture_source" commit -q -m "remote divergence"
git -C "$fixture_source" push -q origin main
printf 'local\n' >"$fixture_checkout/local-version.txt"
git -C "$fixture_checkout" add local-version.txt
git -C "$fixture_checkout" commit -q -m "local divergence"
if divergence_output="$(UPDATE_TEST_TRACE="$fixture_trace" "$fixture_checkout/tools/update.sh" 2>&1)"; then
    fail "divergent root unexpectedly updated"
fi
assert_not_contains "$(cat "$fixture_trace")" "autoproj"

create_fixture package-failure
set +e
UPDATE_TEST_TRACE="$fixture_trace" UPDATE_TEST_AUTOPROJ_STATUS=23 \
    "$fixture_checkout/tools/update.sh" >"$fixture_root/output.log" 2>&1
package_status=$?
set -e
[ "$package_status" -eq 23 ] ||
    fail "Autoproj failure status was not preserved: $package_status"
failure_trace="$(cat "$fixture_trace")"
assert_contains "$failure_trace" "autoproj <update>"
assert_not_contains "$failure_trace" "reset"
assert_not_contains "$failure_trace" "build"

printf 'workspace source update tests passed\n'
