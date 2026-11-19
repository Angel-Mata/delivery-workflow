#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"
GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo 'no-git')"
APP_IMAGE="${APP_IMAGE:-delivery-demo:${VERSION}-${GIT_SHA}}"
FAIL_READINESS="${FAIL_READINESS:-false}"
APP_PORT="${APP_PORT:-8000}"
VERIFY_TIMEOUT="${VERIFY_TIMEOUT:-10}"

STATE_DIR=".deploy-state"
LKG_FILE="${STATE_DIR}/last_known_good.env"
mkdir -p "${STATE_DIR}"

IMAGE_ID="$(docker image inspect --format '{{.Id}}' "${APP_IMAGE}")"
echo "[deploy] Starting deployment: image=${APP_IMAGE} (id=${IMAGE_ID}), FAIL_READINESS=${FAIL_READINESS}"

APP_IMAGE="${APP_IMAGE}" FAIL_READINESS="${FAIL_READINESS}" APP_PORT="${APP_PORT}" \
  docker compose up -d --force-recreate

if ./scripts/verify.sh "${VERSION}" "${VERIFY_TIMEOUT}"; then
  cat > "${LKG_FILE}" <<EOF
APP_VERSION=${VERSION}
APP_IMAGE=${APP_IMAGE}
IMAGE_ID=${IMAGE_ID}
FAIL_READINESS=${FAIL_READINESS}
APP_PORT=${APP_PORT}
DEPLOYED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
  echo "[deploy] SUCCESS: Release ${APP_IMAGE} deployed and recorded as last_known_good."
  exit 0
else
  echo "[deploy] FAILURE: Release ${APP_IMAGE} failed verification."
  echo "[deploy] Last logs from failed container:"
  docker logs --tail 15 delivery-demo-app || true

  if [ -f "${LKG_FILE}" ]; then
    echo "[deploy] Triggering automatic rollback to last known good release..."
    ./scripts/rollback.sh
    echo "[deploy] Rollback completed, but deployment of ${APP_IMAGE} is reported as FAILED (exit 1)."
  else
    echo "[deploy] No previous release available for rollback."
  fi
  exit 1
fi
