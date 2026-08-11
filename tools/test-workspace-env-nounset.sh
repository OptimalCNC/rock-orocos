#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/common.sh"

test_root="$(mktemp -d "${TMPDIR:-/tmp}/orocos-rock-workspace-env.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/.autoproj"
cat >"$test_root/.autoproj/env.sh" <<'EOF'
if test -z "$PYTHONPATH"; then
    PYTHONPATH="/fixture/python"
fi
export PYTHONPATH
AUTOPROJ_FIXTURE_SOURCED=1
export AUTOPROJ_FIXTURE_SOURCED
EOF
cat >"$test_root/.bundle_env.sh" <<'EOF'
BUNDLE_FIXTURE_SOURCED=1
export BUNDLE_FIXTURE_SOURCED
EOF
cat >"$test_root/env.sh" <<EOF
. "$test_root/.autoproj/env.sh"
. "$test_root/.bundle_env.sh"
EOF

OROCOS_ROCK_ROOT="$test_root"
unset PYTHONPATH
orocos_rock_source_workspace_env

[ "$AUTOPROJ_FIXTURE_SOURCED" = 1 ] ||
    orocos_rock_die "Autoproj workspace environment was not sourced"
[ "$BUNDLE_FIXTURE_SOURCED" = 1 ] ||
    orocos_rock_die "bundle workspace environment was not sourced"
[ "$PYTHONPATH" = "/fixture/python" ] ||
    orocos_rock_die "workspace PYTHONPATH was not preserved"
case "$-" in
    *u*) ;;
    *) orocos_rock_die "nounset was not restored after successful workspace environment sourcing" ;;
esac
if ( : "$NOUNSET_SUCCESS_PROBE" ) 2>/dev/null; then
    orocos_rock_die "nounset is not active after successful workspace environment sourcing"
fi

cat >"$test_root/env.sh" <<'EOF'
WORKSPACE_ENV_FAILURE_FIXTURE=1
export WORKSPACE_ENV_FAILURE_FIXTURE
return 37
EOF

if orocos_rock_source_workspace_env; then
    orocos_rock_die "failing workspace environment unexpectedly succeeded"
else
    source_status=$?
fi
[ "$source_status" -eq 37 ] ||
    orocos_rock_die "workspace environment failure status was not preserved: $source_status"
[ "$WORKSPACE_ENV_FAILURE_FIXTURE" = 1 ] ||
    orocos_rock_die "workspace environment changes before failure were not preserved"
case "$-" in
    *u*) ;;
    *) orocos_rock_die "nounset was not restored after failed workspace environment sourcing" ;;
esac
if ( : "$NOUNSET_FAILURE_PROBE" ) 2>/dev/null; then
    orocos_rock_die "nounset is not active after failed workspace environment sourcing"
fi
