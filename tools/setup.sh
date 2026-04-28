#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'USAGE'
Usage: ./tools/setup.sh [--prefix PREFIX]

Install Autoproj, bootstrap the Orocos/Rock workspace, install the selected
toolchain packages, and validate the installed prefix.

Options:
  --prefix PREFIX  Installed toolchain prefix. Default: $OROCOS_ROCK_PREFIX or ~/.orocos
  -h, --help       Show this help
USAGE
}

PREFIX="$OROCOS_ROCK_DEFAULT_PREFIX"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --prefix)
            [ "$#" -ge 2 ] || orocos_rock_die "--prefix requires a value"
            PREFIX="$2"
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

"$SCRIPT_DIR/install-autoproj.sh"
"$SCRIPT_DIR/bootstrap.sh" --prefix "$PREFIX"
"$SCRIPT_DIR/install.sh" --prefix "$PREFIX"
"$SCRIPT_DIR/validate-install.sh" --prefix "$PREFIX"
