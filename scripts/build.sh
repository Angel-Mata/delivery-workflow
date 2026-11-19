#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"
GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo 'no-git')"
BUILD_TIME="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
IMAGE="delivery-demo:${VERSION}-${GIT_SHA}"

echo "[build] Building ${IMAGE} (git_sha=${GIT_SHA}, build_time=${BUILD_TIME})..."

docker build \
  --build-arg APP_VERSION="${VERSION}" \
  --build-arg GIT_SHA="${GIT_SHA}" \
  --build-arg BUILD_TIME="${BUILD_TIME}" \
  -t "${IMAGE}" \
  .

IMAGE_ID="$(docker image inspect --format '{{.Id}}' "${IMAGE}")"
echo "[build] Image ready: ${IMAGE} (id=${IMAGE_ID})"
