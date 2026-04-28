#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'USAGE'
Usage: ./tools/bootstrap.sh [--prefix PREFIX] [--skip-osdeps]

Refresh the Autoproj workspace configuration for the MetaNC Orocos/Rock
toolchain dependency.

Options:
  --prefix PREFIX  Installed toolchain prefix. Default: $OROCOS_ROCK_PREFIX or ~/.orocos
  --skip-osdeps   Do not run "autoproj osdeps"
  -h, --help      Show this help
USAGE
}

INSTALL_OSDEPS=1
PREFIX="$OROCOS_ROCK_DEFAULT_PREFIX"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --prefix)
            [ "$#" -ge 2 ] || orocos_rock_die "--prefix requires a value"
            PREFIX="$2"
            shift 2
            ;;
        --skip-osdeps)
            INSTALL_OSDEPS=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            orocos_rock_die "unknown argument: $1"
            ;;
    esac
done

orocos_rock_require_file "$OROCOS_ROCK_ROOT/autoproj/manifest"
orocos_rock_require_autoproj
orocos_rock_source_workspace_env
if [ "$INSTALL_OSDEPS" -eq 1 ]; then
    orocos_rock_prepare_autoproj_workspace "$PREFIX" "all"
else
    orocos_rock_prepare_autoproj_workspace "$PREFIX" "none"
fi

cd "$OROCOS_ROCK_ROOT"

orocos_rock_info "Refreshing Autoproj configuration"
orocos_rock_autoproj reconfigure --no-interactive

if [ "$INSTALL_OSDEPS" -eq 1 ]; then
    orocos_rock_info "Installing operating-system dependencies through Autoproj"
    orocos_rock_autoproj osdeps --no-interactive
fi
