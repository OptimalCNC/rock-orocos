#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

UBUNTU_VERSION="${UBUNTU_VERSION:-24.04}"
IMAGE_NAME="${OROCOS_ROCK_DOCKER_IMAGE:-orocos-rock:ubuntu-$UBUNTU_VERSION}"

docker build \
    --build-arg "UBUNTU_VERSION=$UBUNTU_VERSION" \
    --file "$ROOT_DIR/docker/orocos-rock/Dockerfile" \
    --tag "$IMAGE_NAME" \
    "$@" \
    "$ROOT_DIR"
