#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'USAGE'
Usage: ./tools/test-opcua-custom-datatypes.sh --prefix PREFIX --dependency-prefix PREFIX [--target TARGET]

Build and install RTT, rtt_opcua, OCL, and an external custom-datatype fixture
into an isolated temporary prefix, then run the fixture server and client as
separate processes.

Options:
  --prefix PREFIX
      Required empty install prefix below /tmp.
  --dependency-prefix PREFIX
      Temporary prefix below /tmp containing farbot, rtlog-cpp, open62541, and
      open62541pp.
  --target gnulinux|xenomai
      Orocos target. Default: gnulinux.
  -h, --help
      Show this help.
USAGE
}

PREFIX=""
DEPENDENCY_PREFIX="${OROCOS_ROCK_OPCUA_DEPENDENCY_PREFIX:-}"
TARGET="gnulinux"
BUILD_PARALLEL="${JOBS:-2}"
TEST_TIMEOUT="${OPCUA_CUSTOM_DATATYPE_TEST_TIMEOUT:-180}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --prefix)
            [ "$#" -ge 2 ] || orocos_rock_die "--prefix requires a value"
            PREFIX="$2"
            shift 2
            ;;
        --dependency-prefix)
            [ "$#" -ge 2 ] || orocos_rock_die "--dependency-prefix requires a value"
            DEPENDENCY_PREFIX="$2"
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

[ -n "$PREFIX" ] || orocos_rock_die "--prefix is required"
[ -n "$DEPENDENCY_PREFIX" ] || \
    orocos_rock_die "--dependency-prefix is required"
orocos_rock_validate_target "$TARGET"

PREFIX="$(realpath -m -- "$PREFIX")"
DEPENDENCY_PREFIX="$(realpath -m -- "$DEPENDENCY_PREFIX")"
HOME_ROOT="$(cd "$HOME" && pwd -P)"
HOME_OROCOS="$HOME_ROOT/.orocos"
HOME_OROCOS_REAL="$(realpath -m -- "$HOME_OROCOS")"

case "$PREFIX" in
    /tmp/*) ;;
    *) orocos_rock_die "test prefix must be below /tmp: $PREFIX" ;;
esac
case "$DEPENDENCY_PREFIX" in
    /tmp/*) ;;
    *) orocos_rock_die \
        "dependency prefix must be below /tmp: $DEPENDENCY_PREFIX" ;;
esac
case "$PREFIX/" in
    "$HOME_OROCOS/"*|"$HOME_OROCOS_REAL/"*)
        orocos_rock_die "refusing home Orocos prefix: $PREFIX"
        ;;
esac
case "$DEPENDENCY_PREFIX/" in
    "$HOME_OROCOS/"*|"$HOME_OROCOS_REAL/"*)
        orocos_rock_die "refusing home Orocos dependency prefix: $DEPENDENCY_PREFIX"
        ;;
esac

if [ -e "$PREFIX" ] && [ ! -d "$PREFIX" ]; then
    orocos_rock_die "test prefix is not a directory: $PREFIX"
fi
mkdir -p "$PREFIX"
if find "$PREFIX" -mindepth 1 -print -quit | grep -q .; then
    orocos_rock_die "test prefix must be empty: $PREFIX"
fi

for required in \
    "$OROCOS_ROCK_ROOT/toolchain/tools/rtt/CMakeLists.txt" \
    "$OROCOS_ROCK_ROOT/toolchain/tools/rtt_opcua/CMakeLists.txt" \
    "$OROCOS_ROCK_ROOT/toolchain/tools/ocl/CMakeLists.txt" \
    "$OROCOS_ROCK_ROOT/tests/opcua-custom-datatypes/CMakeLists.txt" \
    "$DEPENDENCY_PREFIX/lib/cmake/farbot/farbotConfig.cmake" \
    "$DEPENDENCY_PREFIX/lib/cmake/rtlog/rtlogConfig.cmake" \
    "$DEPENDENCY_PREFIX/lib/cmake/open62541/open62541Config.cmake" \
    "$DEPENDENCY_PREFIX/lib/cmake/open62541pp/open62541ppConfig.cmake"
do
    orocos_rock_require_file "$required"
done

TEST_ROOT="${PREFIX}-work"
if [ -e "$TEST_ROOT" ]; then
    orocos_rock_die "test work directory already exists: $TEST_ROOT"
fi
TEST_HOME="$TEST_ROOT/home"
mkdir -p "$TEST_HOME"

unset OROCOS_PREFIX OROCOS_TARGET LD_LIBRARY_PATH RTT_COMPONENT_PATH
unset CMAKE_PREFIX_PATH PKG_CONFIG_PATH RUBYLIB
export HOME="$TEST_HOME"
export OROCOS_TARGET="$TARGET"

LIBRARY_PATHS=(
    "$PREFIX/lib"
    "$PREFIX/lib/orocos/$TARGET"
    "$PREFIX/lib/orocos/$TARGET/plugins"
    "$PREFIX/lib/orocos/$TARGET/types"
    "$PREFIX/lib/orocos/$TARGET/rtt_opcua"
    "$PREFIX/lib/orocos/$TARGET/rtt_opcua/plugins"
    "$PREFIX/lib/orocos/$TARGET/rtt_opcua/types"
    "$PREFIX/lib/orocos/$TARGET/ocl"
    "$PREFIX/lib/orocos/$TARGET/ocl/plugins"
    "$PREFIX/lib/orocos/$TARGET/ocl/types"
    "$DEPENDENCY_PREFIX/lib"
)
LD_LIBRARY_PATH="$(IFS=:; printf '%s' "${LIBRARY_PATHS[*]}")"
export LD_LIBRARY_PATH

HOME_IGNORE="$HOME_OROCOS;$HOME_OROCOS/toolchain;$HOME_OROCOS_REAL;$HOME_OROCOS_REAL/toolchain"
COMMON_CMAKE_ARGS=(
    -DCMAKE_BUILD_TYPE=RelWithDebInfo
    -DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF
    -DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF
    -DCMAKE_IGNORE_PREFIX_PATH="$HOME_IGNORE"
)

configure_build_install() {
    name="$1"
    source_dir="$2"
    prefix_path="$3"
    shift 3
    build_dir="$TEST_ROOT/$name-build"

    orocos_rock_info "Configuring $name"
    cmake -S "$source_dir" -B "$build_dir" \
        "${COMMON_CMAKE_ARGS[@]}" \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_PREFIX_PATH="$prefix_path" \
        "$@"
    orocos_rock_info "Building $name"
    cmake --build "$build_dir" --parallel "$BUILD_PARALLEL"
    orocos_rock_info "Installing $name into $PREFIX"
    cmake --install "$build_dir"
}

configure_build_install \
    rtt "$OROCOS_ROCK_ROOT/toolchain/tools/rtt" "$DEPENDENCY_PREFIX" \
    -DOROCOS_TARGET="$TARGET" \
    -DENABLE_CORBA=OFF \
    -DENABLE_MQ=OFF \
    -DENABLE_TESTS=ON \
    -DBUILD_TESTING=ON

cmake --build "$TEST_ROOT/rtt-build" --parallel "$BUILD_PARALLEL" \
    --target typekit_test
ctest --test-dir "$TEST_ROOT/rtt-build" --output-on-failure \
    --timeout "$TEST_TIMEOUT" -R '^typekit_test$'

INSTALLED_PREFIX_PATH="$PREFIX;$DEPENDENCY_PREFIX"
configure_build_install \
    rtt-opcua "$OROCOS_ROCK_ROOT/toolchain/tools/rtt_opcua" \
    "$INSTALLED_PREFIX_PATH" \
    -DBUILD_TESTING=ON \
    -DRTT_OPCUA_WARNINGS_AS_ERRORS=ON
ctest --test-dir "$TEST_ROOT/rtt-opcua-build" --output-on-failure \
    --timeout "$TEST_TIMEOUT"

configure_build_install \
    ocl "$OROCOS_ROCK_ROOT/toolchain/tools/ocl" \
    "$INSTALLED_PREFIX_PATH" \
    -DBUILD_TESTING=ON \
    -DBUILD_TESTS=ON \
    -DBUILD_DEPLOYMENT=ON \
    -DBUILD_TASKBROWSER=ON \
    -DBUILD_OPCUA=ON
cmake --build "$TEST_ROOT/ocl-build" --parallel "$BUILD_PARALLEL" \
    --target ocl_opcua_deployment_test deployer-opcua ctaskbrowser-opcua
ctest --test-dir "$TEST_ROOT/ocl-build" --output-on-failure \
    --timeout "$TEST_TIMEOUT" \
    -R '^(ocl_opcua_deployment_test|ctaskbrowser_opcua_.*)$'

configure_build_install \
    fixture "$OROCOS_ROCK_ROOT/tests/opcua-custom-datatypes" \
    "$INSTALLED_PREFIX_PATH"

PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$DEPENDENCY_PREFIX/lib/pkgconfig"
export PKG_CONFIG_PATH
pkg-config --exists "orocos-rtt-$TARGET"
pkg-config --exists "rtt_opcua-$TARGET"
pkg-config --exists "orocos_opcua_fixture-$TARGET"

TYPEKIT="$PREFIX/lib/orocos/$TARGET/orocos_opcua_fixture/types/libfixture-types-$TARGET.so"
TRANSPORT="$PREFIX/lib/orocos/$TARGET/orocos_opcua_fixture/plugins/libfixture-opcua-transport-$TARGET.so"
SERVER="$PREFIX/bin/fixture-server"
CLIENT="$PREFIX/bin/fixture-client"
for artifact in "$TYPEKIT" "$TRANSPORT" "$SERVER" "$CLIENT"; do
    orocos_rock_require_file "$artifact"
done

cd "$TEST_ROOT"

PORT="$(ruby -rsocket -e 'server = TCPServer.new("127.0.0.1", 0); puts server.addr[1]')"
READY_FILE="$TEST_ROOT/server.ready"
SERVER_LOG="$TEST_ROOT/server.log"
SERVER_PID=""

stop_server() {
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill -TERM "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
}
trap stop_server EXIT INT TERM

orocos_rock_info "Starting external fixture server on loopback port $PORT"
"$SERVER" \
    --typekit "$TYPEKIT" \
    --transport "$TRANSPORT" \
    --port "$PORT" \
    --ready "$READY_FILE" >"$SERVER_LOG" 2>&1 &
SERVER_PID="$!"

ready=0
for _ in $(seq 1 200); do
    if [ -s "$READY_FILE" ]; then
        ready=1
        break
    fi
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        break
    fi
    sleep 0.05
done
if [ "$ready" -ne 1 ]; then
    sed -n '1,240p' "$SERVER_LOG" >&2
    orocos_rock_die "fixture server did not become ready"
fi

ENDPOINT="$(sed -n '1p' "$READY_FILE")"
orocos_rock_info "Running external fixture client against $ENDPOINT"
"$CLIENT" \
    --typekit "$TYPEKIT" \
    --transport "$TRANSPORT" \
    --endpoint "$ENDPOINT"

if kill -0 "$SERVER_PID" 2>/dev/null; then
    kill -TERM "$SERVER_PID"
fi
if ! wait "$SERVER_PID"; then
    sed -n '1,240p' "$SERVER_LOG" >&2
    orocos_rock_die "fixture server failed during shutdown"
fi
SERVER_PID=""
trap - EXIT INT TERM

for binary in "$SERVER" "$CLIENT" "$TYPEKIT" "$TRANSPORT"; do
    ldd "$binary" >"$TEST_ROOT/$(basename "$binary").ldd"
done

CONTAMINATION="$({
    rg -F -e "$HOME_OROCOS" -e "$HOME_OROCOS_REAL" \
        "$TEST_ROOT" "$PREFIX" \
        --glob 'CMakeCache.txt' --glob '*.ldd' --glob '*.log' \
        --glob '*.pc' --glob '*.cmake' --glob '*.sh' || true
} | rg -v 'CMAKE_IGNORE_PREFIX_PATH' || true)"
if [ -n "$CONTAMINATION" ]; then
    printf '%s\n' "$CONTAMINATION" >&2
    orocos_rock_die "isolated verification resolved an artifact below $HOME_OROCOS"
fi

orocos_rock_info "OPC UA custom datatype verification passed"
orocos_rock_info "Install prefix: $PREFIX"
orocos_rock_info "Evidence directory: $TEST_ROOT"
