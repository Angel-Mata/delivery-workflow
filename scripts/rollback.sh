#!/usr/bin/env bash
set -euo pipefail

STATE_DIR=".deploy-state"
LKG_FILE="${STATE_DIR}/last_known_good.env"

if [ ! -f "${LKG_FILE}" ]; then
  echo "[rollback] ERROR: No existe un release previo conocido (${LKG_FILE})."
  exit 1
fi

# shellcheck disable=SC1090
source "${LKG_FILE}"

echo "[rollback] Restaurando último release sano: version=${APP_VERSION} (FAIL_READINESS=${FAIL_READINESS})..."

APP_VERSION="${APP_VERSION}" FAIL_READINESS="${FAIL_READINESS}" APP_PORT="${APP_PORT:-8000}" \
  docker compose up -d --force-recreate

./scripts/verify.sh "${APP_VERSION}" 15
echo "[rollback] OK: Release ${APP_VERSION} restaurado y verificado."
