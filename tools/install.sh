#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'USAGE'
Usage: ./tools/install.sh [--prefix PREFIX] [--no-export-env] [-- PACKAGE...]

Update and build the selected Autoproj package layout for the MetaNC
Orocos/Rock toolchain dependency, then refresh the exported environment scripts.

Options:
  --prefix PREFIX  Installed toolchain prefix. Default: $OROCOS_PREFIX or ~/.orocos
  --no-export-env  Do not regenerate PREFIX/env.sh and PREFIX/dev-env.sh after build
  -h, --help       Show this help

Arguments after "--" are passed to "autoproj build".
USAGE
}

PREFIX="$OROCOS_ROCK_DEFAULT_PREFIX"
EXPORT_ENV=1
BUILD_ARGS=()
FORKED_PACKAGES=(rtt ocl log4cpp)

while [ "$#" -gt 0 ]; do
    case "$1" in
        --prefix)
            [ "$#" -ge 2 ] || orocos_rock_die "--prefix requires a value"
            PREFIX="$2"
            shift 2
            ;;
        --no-export-env)
            EXPORT_ENV=0
            shift
            ;;
        --)
            shift
            BUILD_ARGS=("$@")
            break
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
orocos_rock_ensure_workspace_ruby_gems
orocos_rock_source_workspace_env
orocos_rock_prepare_autoproj_workspace "$PREFIX" "none"

cd "$OROCOS_ROCK_ROOT"

orocos_rock_info "Updating Autoproj sources"
orocos_rock_autoproj update --no-interactive --no-osdeps --no-config --no-bundler --no-autoproj "${FORKED_PACKAGES[@]}"

orocos_rock_info "Installing source-declared operating-system dependencies"
orocos_rock_autoproj osdeps --no-interactive

orocos_rock_info "Building Autoproj layout"
orocos_rock_autoproj build --no-interactive "${BUILD_ARGS[@]}"

"$SCRIPT_DIR/install-ruby-tools.sh" --prefix "$PREFIX"

if [ "$EXPORT_ENV" -eq 1 ]; then
    "$SCRIPT_DIR/export-env.sh" --prefix "$PREFIX"
fi
