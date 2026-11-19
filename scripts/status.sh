#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:${APP_PORT:-8000}}"
CURL_OPTS=(--connect-timeout 2 --max-time 3)

echo "=== Container Status ==="
docker ps --filter "name=delivery-demo-app" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "=== Last Known Good Release ==="
if [ -f .deploy-state/last_known_good.env ]; then
  cat .deploy-state/last_known_good.env
else
  echo "(none)"
fi

echo ""
echo "=== Live Endpoints ==="
echo -n "GET /version:      "; curl -s "${CURL_OPTS[@]}" "${BASE_URL}/version" || echo "unreachable"; echo ""
echo -n "GET /health/live:  "; curl -s "${CURL_OPTS[@]}" "${BASE_URL}/health/live" || echo "unreachable"; echo ""
echo -n "GET /health/ready: "; curl -s "${CURL_OPTS[@]}" "${BASE_URL}/health/ready" || echo "unreachable"; echo ""

echo ""
echo "=== Last 10 Logs ==="
docker logs --tail 10 delivery-demo-app 2>/dev/null || echo "(no logs)"
