#!/usr/bin/env bash
# First-time install or full redeploy of the Hydralis backend stack.
# Run from the deploy/ directory on the server.
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -f .env ]; then
  echo "deploy/.env not found. Copy .env.example to .env and fill in values first."
  exit 1
fi

echo "==> Pulling Caddy image"
docker compose pull caddy

echo "==> Building and starting backend + Caddy"
docker compose up -d --build

echo "==> Waiting for backend health"
for i in $(seq 1 30); do
  if docker compose exec -T backend curl -fsS http://127.0.0.1:8000/health >/dev/null 2>&1; then
    echo "Backend healthy."
    break
  fi
  sleep 2
done

echo
echo "Stack is up. Live logs: docker compose logs -f"
echo "Health endpoint: https://$(grep HYDRALIS_DOMAIN .env | cut -d= -f2)/health"
