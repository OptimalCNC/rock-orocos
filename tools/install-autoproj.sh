#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'USAGE'
Usage: ./tools/install-autoproj.sh

Install the Autoproj Ruby gem into the current user's gem directory when the
"autoproj" command is not already available.

The script does not modify shell startup files. If RubyGems installs executables
outside PATH, it prints the PATH entry to add for the current shell.
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

[ "$#" -eq 0 ] || {
    usage >&2
    orocos_rock_die "unknown argument: $1"
}

orocos_rock_retry() {
    attempts="$1"
    shift

    attempt=1
    while true; do
        if "$@"; then
            return 0
        fi

        if [ "$attempt" -ge "$attempts" ]; then
            return 1
        fi

        orocos_rock_info "Command failed, retrying ($attempt/$attempts): $*"
        attempt=$((attempt + 1))
        sleep 2
    done
}

if command -v autoproj >/dev/null 2>&1; then
    orocos_rock_info "autoproj is already available: $(command -v autoproj)"
    exit 0
fi

orocos_rock_require_command ruby
orocos_rock_require_command gem
orocos_rock_require_command curl

FACETS_GEM_URL="https://rubygems.org/downloads/facets-3.1.0.gem"
FACETS_GEM_PATH="${TMPDIR:-/tmp}/facets-3.1.0.gem"

if ruby -e 'gem "facets", "= 3.1.0"; require "facets/kernel/constant"' >/dev/null 2>&1; then
    orocos_rock_info "Facets 3.1.0 is already available"
else
    orocos_rock_info "Downloading Facets 3.1.0 gem artifact"
    orocos_rock_retry 5 curl --fail --location --retry 5 --retry-delay 2 --retry-connrefused \
        --output "$FACETS_GEM_PATH" "$FACETS_GEM_URL"

    orocos_rock_info "Installing Facets version compatible with utilrb"
    gem install --user-install --local --no-document "$FACETS_GEM_PATH"
fi

orocos_rock_info "Installing Autoproj with RubyGems"
orocos_rock_retry 5 gem install --user-install --conservative --no-document autoproj

USER_GEM_HOME="$(orocos_rock_user_gem_home)"
USER_GEM_BIN="$USER_GEM_HOME/bin"
USER_GEM_PATH="$(orocos_rock_user_gem_path)"

if GEM_PATH="$USER_GEM_PATH" \
    ruby -e 'gem "facets", "< 3.2"; gem "autoproj"; require "facets/kernel/constant"' >/dev/null 2>&1; then
    orocos_rock_info "autoproj installed under $USER_GEM_BIN"
    orocos_rock_info "For this shell, run:"
    orocos_rock_info "  export PATH=\"$USER_GEM_BIN:\$PATH\""
else
    orocos_rock_die "autoproj install finished, but Autoproj Ruby gems are not usable with GEM_PATH=$USER_GEM_PATH"
fi
