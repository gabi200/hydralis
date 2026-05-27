# Self-Hosting the Hydralis Backend

This guide walks you from a fresh Linux server to a fully working production
deployment of the Hydralis FastAPI backend, with HTTPS, WebSockets, persistent
storage, and one-command updates.

The end state:

- `https://api.your-domain.tld/health` returns `{"status":"ok"}`
- `wss://api.your-domain.tld/api/v1/stream` accepts WebSocket connections
- The Firebase-hosted Nuxt dashboard talks to it through `NUXT_PUBLIC_API_BASE`
- The Flutter app talks to it through `--dart-define=API_BASE=...`
- Updates are `cd ~/hydralis/deploy && ./update.sh`

Everything lives in the `deploy/` directory of this repository.

---

## 1. What you need before you start

| Item | Why |
|---|---|
| A Linux server (Ubuntu 22.04 / 24.04 LTS recommended) with **public IP** | Caddy needs to reach Let's Encrypt on ports 80 + 443 to issue the TLS cert. |
| A domain name (or subdomain) | The Hydralis dashboard and mobile app need `wss://` from an HTTPS origin; HTTPS requires a domain + cert. A free subdomain on Cloudflare/Duck DNS works. |
| **Two open inbound ports**: 80 (TLS challenge) and 443 (HTTPS + WSS) | Browsers connect on 443. Port 80 is only used during certificate renewal. Anything else can stay closed. |
| SSH access as a non-root user with `sudo` | All commands assume `ubuntu@server`. |
| 1 GB RAM minimum, 1 vCPU, 10 GB disk | The FastAPI + Caddy stack uses ~150 MB RAM at idle. SQLite grows slowly. |

**About the architecture:** the backend runs in one container (`hydralis-backend`)
listening on port 8000 inside Docker's private network. Caddy runs in a second
container (`hydralis-caddy`) that owns ports 80 + 443, terminates TLS, and
reverse-proxies everything to the backend — including WebSocket upgrades. The
SQLite database lives in a Docker named volume `backend_data` so it survives
container restarts and updates.

---

## 2. Point your domain at the server

In your DNS provider, create an **A record**:

```
Type:   A
Name:   api          (or whatever subdomain you want)
Value:  <your-server-public-ip>
TTL:    300
```

Wait ~5 minutes, then verify from any machine:

```bash
dig +short api.your-domain.tld
```

You should see the server's IP. If you don't, DNS is the problem — fix this
before going any further. Caddy cannot issue the certificate without working
DNS.

---

## 3. Prepare the server

SSH in and install Docker (one-liner from Docker's official script):

```bash
ssh ubuntu@your-server
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
exit
# log back in for the group change to take effect
ssh ubuntu@your-server
docker --version           # sanity check
docker compose version
```

Open the firewall (Ubuntu uses `ufw`):

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status            # confirm 22, 80, 443 are open
```

If your server is on a cloud provider (Hetzner / DO / AWS / OVH), also open
ports 80 + 443 in the provider's security group / cloud firewall. UFW only
controls the OS-level firewall.

---

## 4. Clone the repo

```bash
git clone <your-fork-url> ~/hydralis
cd ~/hydralis/deploy
```

If you cloned into a different path, just adjust the path everywhere below.

---

## 5. Configure the stack

Copy the env template and edit it:

```bash
cp .env.example .env
nano .env
```

Required values:

| Variable | What to put |
|---|---|
| `HYDRALIS_DOMAIN` | The full hostname you created the A record for. Example: `api.hydralis.example.com`. **No `https://`, no trailing slash.** |
| `HYDRALIS_TLS_EMAIL` | Your email. Let's Encrypt uses it for expiry warnings. |
| `JWT_SECRET` | A long random string. Generate one with `openssl rand -hex 48`. Do **not** reuse the placeholder. |
| `CORS_ORIGINS` | The origins allowed to call the API. For the Firebase dashboard set it to `https://hydralis-app.web.app`. To allow both the live dashboard and local dev: `https://hydralis-app.web.app,http://localhost:3000`. |
| `DEMO_MODE` | `true` runs the gas sensor simulator. Set to `false` once real sensors POST to `/api/v1/gas/readings/ingest`. |
| `CDSE_CLIENT_ID` / `CDSE_CLIENT_SECRET` / `EFAS_WMS_TOKEN` | Optional — only needed for live Copernicus flood data. Leave blank for gas-only demos. |

Save and exit (`Ctrl-O`, `Enter`, `Ctrl-X` in nano).

---

## 6. First deploy

From `~/hydralis/deploy`:

```bash
./deploy.sh
```

What this does:

1. Pulls the Caddy image.
2. Builds the backend image from `copernicus-flood-backend/Dockerfile`.
3. Starts both containers detached.
4. Waits up to 60 s for the backend `/health` endpoint to respond.

First boot takes 1–3 minutes (image build + Let's Encrypt cert issuance).
Watch logs in another terminal if you want to see the cert handshake:

```bash
docker compose logs -f caddy
```

You'll see lines like `certificate obtained successfully` when TLS is ready.

Verify the public endpoints:

```bash
curl https://api.your-domain.tld/health
# {"status":"ok"}

curl https://api.your-domain.tld/api/v1/gas/sensors | head
# {"sensors":[{"id":"GS-001", ...
```

Try the WebSocket (needs `websocat` or `wscat`):

```bash
npx -y wscat -c wss://api.your-domain.tld/api/v1/stream
# < {"event":"connected","payload":{"stream":"hydralis"}}
```

If you see the `connected` event, **the system is live in production.**

---

## 7. Point the dashboard at the new backend

Locally (or in CI), build + deploy the Nuxt dashboard with the new URL baked in:

```bash
cd Dashboard
NUXT_PUBLIC_API_BASE=https://api.your-domain.tld npm install
NUXT_PUBLIC_API_BASE=https://api.your-domain.tld npm run build
firebase deploy --only hosting
```

The dashboard's WebSocket composable auto-upgrades the scheme
(`https://...` → `wss://...`), so you do not need a separate WS env variable.

Open `https://hydralis-app.web.app/dashboard/gas` — sensors should populate
live and the siren should arm.

---

## 8. Point the Flutter app at the new backend

Production builds:

```bash
cd Flutter
flutter build apk \
  --release \
  --dart-define=API_BASE=https://api.your-domain.tld
```

Development against the production backend:

```bash
flutter run --dart-define=API_BASE=https://api.your-domain.tld
```

Development against a local backend on the same Wi-Fi network:

```bash
flutter run --dart-define=API_BASE=http://192.168.1.42:8000
```

The default (no `--dart-define`) is `http://10.0.2.2:8000`, which is what an
Android emulator uses to reach the host machine's localhost.

Multiple phones running the same release build all hit the same backend, get
the same WebSocket broadcast, and self-register with unique device IDs. No
extra config per phone.

---

## 9. Daily operations

All commands are run from `~/hydralis/deploy` on the server.

| Task | Command |
|---|---|
| See live logs | `docker compose logs -f` |
| Backend logs only | `docker compose logs -f backend` |
| Caddy / TLS logs | `docker compose logs -f caddy` |
| Restart backend | `docker compose restart backend` |
| Update to latest code | `./update.sh` |
| Backup the database | `./backup.sh` (writes to `deploy/backups/`) |
| Stop everything | `docker compose down` |
| Stop **and wipe** SQLite | `docker compose down -v` ⚠️ |
| Open a shell in the backend | `docker compose exec backend sh` |
| Inspect the SQLite database | `docker compose exec backend python -c "import sqlite3,os; c=sqlite3.connect(os.environ['DATABASE_PATH']); print([r[0] for r in c.execute('select name from sqlite_master where type=\"table\"').fetchall()])"` |

### Updating the deployment

```bash
cd ~/hydralis/deploy
./update.sh
```

`update.sh` pulls `git`, rebuilds only the backend image, recreates the backend
container, and waits for `/health`. Caddy stays up the entire time so the TLS
session is not interrupted.

### Backups

```bash
./backup.sh
```

Snapshots `hydralis.db` into `deploy/backups/hydralis-<UTCdate>.db` using
SQLite's online `.backup` command (safe to run while the backend is serving
traffic). Keeps the last 30 snapshots. Easy to wire into cron:

```bash
crontab -e
# add:
0 3 * * * cd /home/ubuntu/hydralis/deploy && ./backup.sh >> backup.log 2>&1
```

Restore is a manual copy back into the volume:

```bash
docker compose down
docker compose cp backups/hydralis-20260101T030000Z.db backend:/data/hydralis.db
docker compose up -d
```

---

## 10. Troubleshooting

**TLS handshake fails / `your connection is not private`**

- DNS still pointing somewhere else? `dig +short api.your-domain.tld` must
  return the server IP exactly.
- Port 80 must be open *publicly* — Let's Encrypt issues HTTP-01 challenges
  on port 80 even though the final site uses 443.
- Check Caddy logs: `docker compose logs caddy | grep -i acme`.

**WebSocket immediately disconnects**

- Browser console showing `failed: HTTP Authentication failed`? You're hitting
  CORS. Set `CORS_ORIGINS` in `.env` to include the dashboard's origin, then
  `docker compose restart backend`.
- 1006 with no error message usually means the proxy stripped the Upgrade
  header. The provided Caddyfile handles this — if you replaced it, ensure
  any custom block uses `reverse_proxy` (not a raw `header` directive) so
  Caddy auto-forwards `Upgrade` / `Connection: upgrade`.

**Backend container restarts in a loop**

- `docker compose logs backend` to read the traceback.
- Most common cause: bad `JWT_SECRET` quoting in `.env`. Wrap the value in
  double quotes if it contains shell metacharacters.

**Phones don't show up under "Connected Devices"**

- They have to make the first `POST /api/v1/gas/devices` call. That happens
  on app start. Force-quit the app and reopen.
- Confirm the app is hitting the right URL: in the app drawer the device
  label appears once registration succeeds.

**Simulator broadcasts duplicate alerts**

- You're running more than one backend instance. The simulator must run in
  exactly one process. Set `--scale backend=1` if you ever bumped it.

**Database `disk image is malformed`**

- Restore from a backup (see Section 9). Avoid killing the container with
  `docker kill` (use `docker compose down` or `restart`), which truncates the
  WAL mid-write.

---

## 11. Hardening checklist (do these before going public)

- Rotate `JWT_SECRET` to a fresh 96+ character random string.
- Pin `CORS_ORIGINS` to the exact dashboard origin only — drop the wildcard.
- Set `DEMO_MODE=false` once real sensors POST data.
- Run `./backup.sh` from cron at least daily and copy the snapshots off-box
  (rsync to S3 / Backblaze / another VPS).
- Set up `unattended-upgrades` on Ubuntu so the kernel and Docker stay patched.
- Lock SSH down to key auth only (`PasswordAuthentication no` in
  `/etc/ssh/sshd_config`).
- Add fail2ban or Caddy rate-limit middleware if the API gets scraped.
- Move SQLite to managed Postgres when you cross ~50 active users or want
  multi-instance scaling — the schema in `app/database.py` is portable; only
  the connection helper needs swapping.

---

## 12. File map

```
deploy/
├── docker-compose.yml   # backend + Caddy services
├── Caddyfile            # reverse proxy with auto-TLS + WS upgrade
├── .env.example         # template; copy to .env
├── deploy.sh            # first install / full redeploy
├── update.sh            # git pull + rebuild backend, zero TLS downtime
└── backup.sh            # snapshot SQLite into deploy/backups/

copernicus-flood-backend/
├── Dockerfile           # production image (non-root user, /data volume)
└── ...

Dashboard/
├── nuxt.config.ts       # reads NUXT_PUBLIC_API_BASE at build time
└── ...

Flutter/lib/services/
└── api_config.dart      # reads API_BASE from --dart-define
```

That's the whole loop: edit code on your laptop, push to GitHub, SSH to the
server, `./update.sh`. Backend is live, dashboard rebuilds get pushed to
Firebase, and Flutter releases just need the right `--dart-define` flag.
