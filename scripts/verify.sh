#!/usr/bin/env bash
set -euo pipefail

EXPECTED_VERSION="${1:?Uso: $0 <expected_version> [timeout_seconds]}"
TIMEOUT="${2:-15}"
BASE_URL="${BASE_URL:-http://localhost:${APP_PORT:-8000}}"

echo "[verify] Esperando readiness en ${BASE_URL}/health/ready (timeout=${TIMEOUT}s)..."

elapsed=0
ready=false
while [ "${elapsed}" -lt "${TIMEOUT}" ]; do
  http_code="$(curl -s -o /tmp/ready_body.json -w "%{http_code}" "${BASE_URL}/health/ready" || echo "000")"
  if [ "${http_code}" = "200" ]; then
    ready=true
    break
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done

if [ "${ready}" != "true" ]; then
  echo "[verify] ERROR: Timeout (${TIMEOUT}s) esperando readiness. Último HTTP=${http_code}."
  [ -f /tmp/ready_body.json ] && echo "[verify] Respuesta: $(cat /tmp/ready_body.json)"
  exit 1
fi
echo "[verify] OK: /health/ready respondió HTTP 200 en ${elapsed}s."

version_body="$(curl -sf "${BASE_URL}/version")"
if ! echo "${version_body}" | grep -Eq "\"version\"[[:space:]]*:[[:space:]]*\"${EXPECTED_VERSION}\""; then
  echo "[verify] ERROR: Versión inesperada. Esperada=${EXPECTED_VERSION}, Obtenida=${version_body}"
  exit 1
fi
echo "[verify] OK: /version confirmado (${version_body})."

work_code="$(curl -s -o /tmp/work_body.json -w "%{http_code}" "${BASE_URL}/work" || echo "000")"
if [ "${work_code}" != "200" ]; then
  echo "[verify] ERROR: /work falló con HTTP ${work_code}."
  exit 1
fi
echo "[verify] OK: /work respondió HTTP 200 ($(cat /tmp/work_body.json))."
