#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Uso: $0 <version>}"
FAIL_READINESS="${FAIL_READINESS:-false}"
APP_PORT="${APP_PORT:-8000}"
VERIFY_TIMEOUT="${VERIFY_TIMEOUT:-10}"

STATE_DIR=".deploy-state"
LKG_FILE="${STATE_DIR}/last_known_good.env"
mkdir -p "${STATE_DIR}"

echo "[deploy] Iniciando despliegue: version=${VERSION}, FAIL_READINESS=${FAIL_READINESS}"

APP_VERSION="${VERSION}" FAIL_READINESS="${FAIL_READINESS}" APP_PORT="${APP_PORT}" \
  docker compose up -d --force-recreate

if ./scripts/verify.sh "${VERSION}" "${VERIFY_TIMEOUT}"; then
  cat > "${LKG_FILE}" <<EOF
APP_VERSION=${VERSION}
FAIL_READINESS=${FAIL_READINESS}
APP_PORT=${APP_PORT}
DEPLOYED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
  echo "[deploy] ÉXITO: Release ${VERSION} desplegado y guardado como last_known_good."
  exit 0
else
  echo "[deploy] FALLO: El release ${VERSION} no superó la verificación."
  echo "[deploy] Últimos logs del contenedor fallido:"
  docker logs --tail 15 delivery-demo-app || true

  if [ -f "${LKG_FILE}" ]; then
    echo "[deploy] Iniciando rollback automático al último release sano..."
    ./scripts/rollback.sh
    echo "[deploy] Rollback completado, pero el despliegue de ${VERSION} se reporta como FALLIDO (exit 1)."
  else
    echo "[deploy] No hay versión previa para rollback."
  fi
  exit 1
fi
