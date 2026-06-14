#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'USAGE'
Usage: ./tools/setup.sh [--prefix PREFIX] [--target gnulinux|xenomai]

Install Autoproj, bootstrap the Orocos/Rock workspace, install the selected
toolchain packages, and validate the installed prefix.

Options:
  --prefix PREFIX  Installed toolchain prefix. Default: $OROCOS_PREFIX or ~/.orocos
  --target TARGET  Orocos target to build and export. Default: $OROCOS_TARGET or gnulinux
  -h, --help       Show this help
USAGE
}

PREFIX="$OROCOS_ROCK_DEFAULT_PREFIX"
TARGET="$OROCOS_ROCK_DEFAULT_TARGET"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --prefix)
            [ "$#" -ge 2 ] || orocos_rock_die "--prefix requires a value"
            PREFIX="$2"
            shift 2
            ;;
        --target)
            [ "$#" -ge 2 ] || orocos_rock_die "--target requires a value"
            TARGET="$2"
            shift 2
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

orocos_rock_validate_target "$TARGET"
orocos_rock_configure_target_environment "$TARGET"

"$SCRIPT_DIR/install-autoproj.sh"
"$SCRIPT_DIR/bootstrap.sh" --prefix "$PREFIX" --target "$TARGET"
"$SCRIPT_DIR/install.sh" --prefix "$PREFIX" --target "$TARGET"
"$SCRIPT_DIR/validate-install.sh" --prefix "$PREFIX" --target "$TARGET"
