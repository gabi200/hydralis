#!/usr/bin/env bash
# Pull latest code from git, rebuild the backend image, and restart with zero
# downtime to the Caddy proxy (it stays up while backend is recreated).
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Pulling latest from git"
git pull --ff-only

cd deploy

echo "==> Rebuilding backend image"
docker compose build backend

echo "==> Recreating backend container"
docker compose up -d --no-deps backend

echo "==> Waiting for backend health"
for i in $(seq 1 30); do
  if docker compose exec -T backend curl -fsS http://127.0.0.1:8000/health >/dev/null 2>&1; then
    echo "Backend healthy."
    exit 0
  fi
  sleep 2
done

echo "Backend did not become healthy in time. Check: docker compose logs backend"
exit 1
