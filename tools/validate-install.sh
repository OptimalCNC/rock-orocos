#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'USAGE'
Usage: ./tools/validate-install.sh [--prefix PREFIX] [--target gnulinux|xenomai]

Validate the installed Orocos/Rock prefix exported by orocos-rock.

Options:
  --prefix PREFIX  Installed toolchain prefix. Default: $OROCOS_PREFIX or ~/.orocos
  --target TARGET  Orocos target to validate. Default: $OROCOS_TARGET or gnulinux
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
DEPLOYER="$(orocos_rock_target_deployer "$TARGET")"

orocos_rock_require_file "$PREFIX/env.sh"
orocos_rock_require_file "$PREFIX/dev-env.sh"

(
    # shellcheck disable=SC1090
    . "$PREFIX/env.sh"
    export OROCOS_TARGET="$TARGET"
    orocos_rock_require_command "$DEPLOYER"
    deployer_version_output="$("$DEPLOYER" --version 2>&1 || true)"
    if ! orocos_rock_validate_deployer_version_output "$TARGET" "$deployer_version_output"; then
        orocos_rock_die "$DEPLOYER smoke check failed"
    fi
)

(
    # shellcheck disable=SC1090
    . "$PREFIX/dev-env.sh"
    orocos_rock_require_command orogen
    orocos_rock_require_command typegen
    orogen --help >/dev/null
    typegen --help >/dev/null
)

orocos_rock_info "Validated Orocos/Rock $TARGET install prefix: $PREFIX"
