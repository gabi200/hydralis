# Hydralis Flood and Gas Safety Platform

Hydralis is an integrated disaster management platform that covers both **flood monitoring** (Copernicus / Sentinel-1) and **indoor gas safety** (CH4, CO, LPG, multi-gas). It ships three software components plus a hardware concept:

- **Copernicus Flood Backend** (`copernicus-flood-backend/`) — FastAPI service for flood screening, Sentinel Hub / Copernicus integration, EFAS overlays, dispatch alerts, mobile APIs, gas sensor monitoring with a simulator, multi-device push acknowledgement, and WebSocket events.
- **Dispatch Dashboard** (`Dashboard/`) — Nuxt web app for dispatchers, industrial operators, and administrators. Covers flood alerts, satellite intelligence, safe locations, industrial telemetry, subscriptions, and a dedicated **Gas Monitoring** section (live sensors, devices, history, demo controls).
- **Hydralis Mobile App** (`Flutter/`) — Flutter app with three modes selected at launch: **Resident**, **Gas Dashboard**, and **Dispatcher**. Includes a screaming full-screen alarm overlay driven by the backend WebSocket stream, building selection, evacuation flow, and man-down SOS.
- **Flood Monitoring Arduino Circuit** (`Flood_monitoring_Arduino_circuit/`) — hardware concept image for the flood monitoring node.

A `presentation/` folder holds the FloodGuard SCSS 2026 deck and simulator screenshots used for demos.

## System Overview

```text
                         Copernicus Data Space / Sentinel Hub
                                      |
                                      v
Flutter Mobile App  <---- REST ---->  FastAPI Backend  <---- REST ---->  Nuxt Dispatch Dashboard
   (Resident /                        SQLite storage                       (Flood + Gas)
    Gas / Dispatcher)                     |
       |                                  |
       +---------- WebSocket events ------+---------- WebSocket events ------+
                                      |
                                      v
                       EFAS / OSM boundaries · Gas simulator · Devices
```

The backend is the source of truth for flood alerts, mobile users, safe locations, industrial facilities, satellite data, gas sensors, registered phones, and live WebSocket broadcasts. Dashboard and mobile clients consume the same REST + WebSocket surface.

## Repository Layout

```text
.
├── copernicus-flood-backend/        FastAPI backend (flood + gas) and tests
│   └── app/
│       ├── gas.py                   Gas thresholds, classifier, simulator
│       ├── gas_routes.py            /api/v1/gas/* endpoints
│       ├── flood.py                 Sentinel-1 flood screening
│       ├── mobile.py                Mobile auth, alerts, SOS
│       └── ...
├── Dashboard/                       Nuxt dispatch dashboard
│   └── app/pages/dashboard/
│       ├── gas/{index,devices,history}.vue   Gas Monitoring section
│       ├── settings.vue                       Gas Safety Profile + alarm prefs
│       └── alerts.vue, satellite.vue, ...
├── Flutter/                         Flutter mobile app
│   └── lib/screens/
│       ├── mode_select_screen.dart  Resident / Gas / Dispatcher chooser
│       ├── home_screen.dart         Resident home with building + alarms
│       ├── gas_dashboard_screen.dart
│       ├── dashboard_screen.dart    Dispatcher mode
│       └── building_select_screen.dart
├── Flood_monitoring_Arduino_circuit/
├── presentation/                    Deck + simulator screenshots
├── floodguard-backend/              Reserved (in progress)
├── docs/                            Project-level documentation
└── backend_spec.md                  Earlier backend integration spec
```

## Quick Start

Backend first:

```bash
cd copernicus-flood-backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env
uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

The gas simulator starts automatically in demo mode and streams readings every ~15 seconds, with periodic spikes to exercise warning/critical thresholds.

Dashboard:

```bash
cd Dashboard
npm install
NUXT_PUBLIC_API_BASE=http://127.0.0.1:8000 npm run dev
```

Mobile app:

```bash
cd Flutter
flutter pub get
flutter run
```

For the Android emulator the mobile app defaults to `http://10.0.2.2:8000`. For a physical device, set the host LAN IP in `Flutter/lib/services/backend_service.dart`.

## Mobile Modes

On first launch the app shows a **Mode Select** screen and persists the choice in `SharedPreferences` (`hydralis_mode`):

| Mode | Screen | Purpose |
| --- | --- | --- |
| `resident` | `HomeScreen` | Resident view of their building, sensor list, recent alerts, evacuation flow. Receives full-screen screaming alarm overlay on critical events. |
| `gas` | `GasDashboardScreen` | Live gas sensor tiles, online/alert counters, TTS + audio alarm playback. |
| `dispatcher` | `DashboardScreen` | Original dispatcher view (map, alerts, satellite). |

Switching modes is available from the profile / settings inside the app.

## Demo Credentials

The backend seeds demo dashboard users into SQLite at startup.

| Username | Password | Role |
| --- | --- | --- |
| `dispatcher_ion` | `password123` | Dispatcher |
| `dispatcher_ana` | `password123` | Dispatcher |

The mobile app authenticates a demo user automatically:

- Email: `andrei.ionescu@hydralis.com`
- Password: `secure_password`

## Gas Monitoring

Endpoints live under `/api/v1/gas/*`:

- `GET /sensors`, `GET /sensors/{id}`, `GET /sensors/{id}/readings`
- `GET /alerts`, `POST /alerts/{id}/resolve`, `POST /alerts/{id}/ack`, `GET /alerts/{id}/acks`
- `GET /summary`, `GET /buildings`
- `GET /devices`, `POST /devices`, `POST /devices/{id}/heartbeat`
- `POST /readings/ingest` (for real hardware)

Thresholds (ppm) used by `app/gas.py`:

| Sensor | Warning | Critical |
| --- | --- | --- |
| CH4 | 1000 | 5000 |
| CO  | 35   | 200  |
| LPG | 1000 | 5000 |
| MULTI | 1000 | 5000 |

Mobile devices register through `POST /devices` and acknowledge alerts via `POST /alerts/{id}/ack`, so the dashboard can show which phones have seen each event.

### Dashboard Gas Pages

- `dashboard/gas/index.vue` — Live sensors, DEMO badge, **Arm Siren** button (browser requires a user gesture), per-building tiles, active and resolved alerts.
- `dashboard/gas/devices.vue` — Registered phones, platforms, last heartbeat.
- `dashboard/gas/history.vue` — Historical alerts and resolution timeline.
- `dashboard/settings.vue` — **Gas Safety Profile**: auto-arm siren, broadcast to mobile, flash title, default building.

## Important Workflows

### Mobile Screaming Alarm

1. Backend detects a critical gas reading (real or simulated) or publishes a dispatch alert.
2. Backend broadcasts the event over WebSocket (`gas:alert`, `alert:mobile_emergency`).
3. Mobile `HomeScreen` / `GasDashboardScreen` listens via `BackendService` streams.
4. `alarm_overlay.dart` shows a full-screen siren overlay with TTS + audio playback until dismissed.
5. Dismissal posts an acknowledgement to `/api/v1/gas/alerts/{id}/ack`.

### Mobile Man-Down SOS

1. Resident evacuation flow detects zero movement.
2. Mobile calls `POST /api/alerts/trigger`.
3. Backend creates a published dispatch alert (user name, status `Man Down`, mobility level, location).
4. Backend broadcasts `alert:mobile_emergency`.
5. Dashboard shows the SOS alert and reporter metadata.
6. Tapping **I'M FINE** reports `Safe` and marks the latest SOS as `accidental`.

### Copernicus Flood Screening

1. Client requests flood data for a location or area.
2. Backend queries Copernicus Data Space / Sentinel Hub for recent Sentinel-1 scenes.
3. Backend classifies flood likelihood from VV backscatter water fraction with optional baseline comparison.
4. Backend returns JSON results or PNG heatmap overlays.

### Dispatch Alert Lifecycle

```text
draft -> review -> approved -> published -> updated/closed
published -> accidental
```

Mobile SOS alerts are created as `published`; **I'M FINE** changes them to `accidental`.

## Documentation Index

- [Architecture](docs/architecture.md)
- [Development Setup](docs/development.md)
- [API Reference](docs/api-reference.md)
- [Operations and Troubleshooting](docs/operations.md)
- [Backend README](copernicus-flood-backend/README.md)
- [Dashboard README](Dashboard/README.md)
- [Mobile README](Flutter/README.md)
- [Arduino Circuit README](Flood_monitoring_Arduino_circuit/README.md)

## Verification

Backend:

```bash
cd copernicus-flood-backend
PYTHONPATH=. ./.venv/bin/pytest -q
```

Dashboard:

```bash
cd Dashboard
npm run build
```

Mobile:

```bash
cd Flutter
flutter test
flutter analyze
```

## Production Notes

- Replace demo credentials and the JWT secret before deployment.
- Store Copernicus, EFAS, and JWT secrets in environment variables or a secret manager.
- Disable or guard the gas simulator (`set_simulator(None)`) in production; ingest only from real devices via `POST /readings/ingest`.
- Use a production database instead of SQLite for concurrent multi-user deployment.
- Put the backend behind TLS and configure strict CORS origins.
- Validate flood thresholds with local hydrology data, and gas thresholds with the relevant safety standard (e.g. OSHA, EN 50194) before operational use.
