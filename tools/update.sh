#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORIGINAL_ARGS=("$@")
# shellcheck disable=SC1091
. "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'USAGE'
Usage: ./tools/update.sh [--prefix PREFIX] [--target gnulinux|xenomai]

Fast-forward the current root branch from its configured upstream, then update
the complete Autoproj-managed package layout without building or installing.

Options:
  --prefix PREFIX  Workspace install prefix. Default: $OROCOS_PREFIX or ~/.orocos
  --target TARGET  Orocos target to configure. Default: $OROCOS_TARGET or gnulinux
  -h, --help       Show this help
USAGE
}

PREFIX="$OROCOS_ROCK_DEFAULT_PREFIX"
TARGET="$OROCOS_ROCK_DEFAULT_TARGET"
REEXEC_HEAD="${OROCOS_ROCK_UPDATE_REEXEC_HEAD:-}"
unset OROCOS_ROCK_UPDATE_REEXEC_HEAD

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
orocos_rock_require_command git

cd "$OROCOS_ROCK_ROOT"
if ! branch="$(git symbolic-ref --quiet --short HEAD)"; then
    orocos_rock_die "root repository is on a detached HEAD"
fi
if ! upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)"; then
    orocos_rock_die "root branch '$branch' has no configured upstream"
fi
if [ -n "$(git status --porcelain --untracked-files=normal)" ]; then
    orocos_rock_die "root worktree has local changes; commit or remove them before updating"
fi

current_head="$(git rev-parse HEAD)"
if [ -n "$REEXEC_HEAD" ]; then
    [ "$REEXEC_HEAD" = "$current_head" ] ||
        orocos_rock_die "root changed unexpectedly while re-executing the update command"
else
    orocos_rock_info "Updating root branch '$branch' from '$upstream'"
    git pull --ff-only
    updated_head="$(git rev-parse HEAD)"

    if [ "$updated_head" != "$current_head" ]; then
        updated_script="$OROCOS_ROCK_ROOT/tools/update.sh"
        [ -x "$updated_script" ] ||
            orocos_rock_die "updated command is missing or not executable: $updated_script"
        OROCOS_ROCK_UPDATE_REEXEC_HEAD="$updated_head" \
            exec "$updated_script" "${ORIGINAL_ARGS[@]}"
    fi
fi

orocos_rock_require_file "$OROCOS_ROCK_ROOT/autoproj/manifest"
orocos_rock_require_autoproj
orocos_rock_ensure_workspace_ruby_gems
orocos_rock_source_workspace_env
orocos_rock_configure_target_environment "$TARGET"
orocos_rock_prepare_autoproj_workspace "$PREFIX" none "$TARGET"

cd "$OROCOS_ROCK_ROOT"
orocos_rock_info "Updating the complete Autoproj-managed package layout"
orocos_rock_autoproj update \
    --no-interactive \
    --no-osdeps \
    --no-config \
    --no-bundler \
    --no-autoproj

orocos_rock_info "Workspace sources are up to date"
