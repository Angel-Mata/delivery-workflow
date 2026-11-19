#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:${APP_PORT:-8000}}"

echo "=== Estado del contenedor ==="
docker ps --filter "name=delivery-demo-app" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "=== Último release sano registrado ==="
if [ -f .deploy-state/last_known_good.env ]; then
  cat .deploy-state/last_known_good.env
else
  echo "(ninguno)"
fi

echo ""
echo "=== Endpoints en vivo ==="
echo -n "GET /version:      "; curl -s "${BASE_URL}/version" || echo "unreachable"; echo ""
echo -n "GET /health/live:  "; curl -s "${BASE_URL}/health/live" || echo "unreachable"; echo ""
echo -n "GET /health/ready: "; curl -s "${BASE_URL}/health/ready" || echo "unreachable"; echo ""

echo ""
echo "=== Últimos 10 logs ==="
docker logs --tail 10 delivery-demo-app 2>/dev/null || echo "(sin logs)"
