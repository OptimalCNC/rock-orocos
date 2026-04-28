#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'USAGE'
Usage: ./tools/validate-install.sh [--prefix PREFIX]

Validate the installed Orocos/Rock prefix exported by orocos-rock.

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

orocos_rock_require_file "$PREFIX/env.sh"
orocos_rock_require_file "$PREFIX/dev-env.sh"

(
    # shellcheck disable=SC1090
    . "$PREFIX/env.sh"
    orocos_rock_require_command deployer-gnulinux
)

(
    # shellcheck disable=SC1090
    . "$PREFIX/dev-env.sh"
    orocos_rock_require_command orogen
    orocos_rock_require_command typegen
)

orocos_rock_info "Validated Orocos/Rock install prefix: $PREFIX"
