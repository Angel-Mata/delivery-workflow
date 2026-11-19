#!/usr/bin/env bash
set -euo pipefail

EXPECTED_VERSION="${1:?Usage: $0 <expected_version> [timeout_seconds]}"
TIMEOUT="${2:-15}"
BASE_URL="${BASE_URL:-http://localhost:${APP_PORT:-8000}}"
CURL_OPTS=(--connect-timeout 2 --max-time 3)

echo "[verify] Waiting for readiness at ${BASE_URL}/health/ready (timeout=${TIMEOUT}s)..."

SECONDS=0
ready=false
http_code="000"
while [ "${SECONDS}" -lt "${TIMEOUT}" ]; do
  http_code="$(curl -s "${CURL_OPTS[@]}" -o /tmp/ready_body.json -w "%{http_code}" "${BASE_URL}/health/ready" || echo "000")"
  if [ "${http_code}" = "200" ]; then
    ready=true
    break
  fi
  sleep 1
done

if [ "${ready}" != "true" ]; then
  echo "[verify] ERROR: Timeout (${TIMEOUT}s) waiting for readiness. Last HTTP=${http_code}."
  [ -f /tmp/ready_body.json ] && echo "[verify] Response: $(cat /tmp/ready_body.json)"
  exit 1
fi
echo "[verify] OK: /health/ready returned HTTP 200 in ${SECONDS}s."

version_body="$(curl -sf "${CURL_OPTS[@]}" "${BASE_URL}/version")"
if ! echo "${version_body}" | grep -Eq "\"version\"[[:space:]]*:[[:space:]]*\"${EXPECTED_VERSION}\""; then
  echo "[verify] ERROR: Unexpected version. Expected=${EXPECTED_VERSION}, Got=${version_body}"
  exit 1
fi
echo "[verify] OK: /version confirmed (${version_body})."

work_code="$(curl -s "${CURL_OPTS[@]}" -o /tmp/work_body.json -w "%{http_code}" "${BASE_URL}/work" || echo "000")"
if [ "${work_code}" != "200" ]; then
  echo "[verify] ERROR: /work failed with HTTP ${work_code}."
  exit 1
fi
echo "[verify] OK: /work returned HTTP 200 ($(cat /tmp/work_body.json))."
