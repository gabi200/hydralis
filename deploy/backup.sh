#!/usr/bin/env bash
# Copy the SQLite database out of the running container into ./backups/.
# Safe to run while the backend is live (uses SQLite's .backup command).
set -euo pipefail

cd "$(dirname "$0")"
mkdir -p backups

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
target="backups/hydralis-${stamp}.db"

echo "==> Snapshotting database to ${target}"
docker compose exec -T backend python - <<PY
import sqlite3, os
src = os.environ["DATABASE_PATH"]
dst = "/data/_snapshot.db"
con = sqlite3.connect(src)
bck = sqlite3.connect(dst)
with bck:
    con.backup(bck)
con.close()
bck.close()
PY

docker compose cp backend:/data/_snapshot.db "${target}"
docker compose exec -T backend rm -f /data/_snapshot.db

echo "Backup written: ${target}"

# Keep the last 30 snapshots.
ls -1t backups/hydralis-*.db | tail -n +31 | xargs -r rm -f
