#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'USAGE'
Usage: ./tools/check-rtlog-prefix.sh [--prefix PREFIX]

Configure and build a tiny CMake consumer against the installed prefix to prove
that find_package(rtlog CONFIG REQUIRED) exposes rtlog::rtlog.

Options:
  --prefix PREFIX  Installed toolchain prefix. Default: $OROCOS_PREFIX or ~/.orocos
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

DEV_ENV="$PREFIX/dev-env.sh"
orocos_rock_require_file "$DEV_ENV"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/orocos-rtlog-prefix.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

cat > "$WORKDIR/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 3.16)
project(orocos_rtlog_prefix_check LANGUAGES CXX)

find_package(rtlog CONFIG REQUIRED)

add_executable(orocos_rtlog_prefix_check main.cpp)
target_link_libraries(orocos_rtlog_prefix_check PRIVATE rtlog::rtlog)
CMAKE

cat > "$WORKDIR/main.cpp" <<'CPP'
#include <rtlog/rtlog.h>

#include <atomic>
#include <cstddef>

enum class LogLevel {
    Info
};

struct LogData {
    LogLevel level;
};

static std::atomic<std::size_t> sequence{0};

int main()
{
    rtlog::Logger<LogData, 8, 128, sequence> logger;
    auto status = logger.Log({LogLevel::Info}, "prefix check %d", 7);
    return status == rtlog::Status::Success ? 0 : 1;
}
CPP

orocos_rock_info "Checking rtlog CMake package from $PREFIX"
(
    # shellcheck disable=SC1090
    . "$DEV_ENV"
    cmake -S "$WORKDIR" -B "$WORKDIR/build"
    cmake --build "$WORKDIR/build"
    "$WORKDIR/build/orocos_rtlog_prefix_check"
)
