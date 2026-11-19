#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Uso: $0 <version>}"
GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo 'no-git')"
BUILD_TIME="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
IMAGE="delivery-demo:${VERSION}"

echo "[build] Construyendo ${IMAGE} (git_sha=${GIT_SHA}, build_time=${BUILD_TIME})..."

docker build \
  --build-arg APP_VERSION="${VERSION}" \
  --build-arg GIT_SHA="${GIT_SHA}" \
  --build-arg BUILD_TIME="${BUILD_TIME}" \
  -t "${IMAGE}" \
  .

echo "[build] Imagen lista: ${IMAGE}"
