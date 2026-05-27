#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

OROCOS_ROCK_BASE_IMAGE="${OROCOS_ROCK_BASE_IMAGE:-ubuntu:24.04}"
IMAGE_NAME="${OROCOS_ROCK_DOCKER_IMAGE:-orocos-rock:latest}"

docker build \
    --build-arg "OROCOS_ROCK_BASE_IMAGE=$OROCOS_ROCK_BASE_IMAGE" \
    --file "$ROOT_DIR/docker/orocos-rock/Dockerfile" \
    --tag "$IMAGE_NAME" \
    "$@" \
    "$ROOT_DIR"
