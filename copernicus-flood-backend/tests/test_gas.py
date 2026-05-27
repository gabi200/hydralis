from __future__ import annotations

import asyncio
from pathlib import Path
from typing import Any

import pytest

from app.config import Settings
from app.database import connect, initialize_database
from app.gas import (
    BASE_READINGS,
    GasSimulator,
    THRESHOLDS,
    classify,
    thresholds_for,
)
from app.gas_routes import (
    AckAlertRequest,
    IngestReadingRequest,
    RegisterDeviceRequest,
    ack_alert,
    get_readings,
    get_sensor,
    ingest_reading,
    list_acks,
    list_alerts,
    list_buildings,
    list_devices,
    list_sensors,
    register_device,
    resolve_alert,
    summary,
)


EXPECTED_SENSOR_COUNT = 12


class _RecordingBroadcaster:
    def __init__(self) -> None:
        self.events: list[tuple[str, dict[str, Any]]] = []

    async def broadcast(self, event: str, payload: dict[str, Any]) -> None:
        self.events.append((event, payload))


def _settings(tmp_path: Path, name: str = "gas-test.db") -> Settings:
    return Settings(database_path=str(tmp_path / name))


def test_seed_creates_gas_sensors_across_buildings(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    initialize_database(settings)
    with connect(settings) as conn:
        total = conn.execute("SELECT COUNT(*) FROM gas_sensors").fetchone()[0]
        buildings = {
            row["building_id"]
            for row in conn.execute("SELECT DISTINCT building_id FROM gas_sensors").fetchall()
        }
        types = {
            row["sensor_type"]
            for row in conn.execute("SELECT DISTINCT sensor_type FROM gas_sensors").fetchall()
        }
    assert total == EXPECTED_SENSOR_COUNT
    assert buildings >= {
        "BLD-TITAN",
        "BLD-FLOREASCA",
        "BLD-MILITARI",
        "BLD-UNIRII",
        "BLD-POLITEHNICA",
    }
    assert {"CH4", "CO", "LPG", "MULTI"}.issubset(types)


def test_thresholds_are_defined_for_known_types() -> None:
    for sensor_type in ("CH4", "CO", "LPG", "MULTI"):
        th = thresholds_for(sensor_type)
        assert th.critical > th.warning > 0


def test_classify_returns_normal_warning_critical() -> None:
    assert classify("CH4", BASE_READINGS["CH4"]) == "normal"
    assert classify("CH4", THRESHOLDS["CH4"].warning + 1) == "warning"
    assert classify("CH4", THRESHOLDS["CH4"].critical + 1) == "critical"
    assert classify("CO", THRESHOLDS["CO"].warning + 1) == "warning"


def test_list_sensors_route_returns_seeded_sensors(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    initialize_database(settings)
    with connect(settings) as conn:
        result = list_sensors(conn=conn)
    assert len(result["sensors"]) == EXPECTED_SENSOR_COUNT
    assert "CH4" in result["thresholds"]
    assert "CO" in result["thresholds"]


def test_get_sensor_404_when_missing(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    initialize_database(settings)
    from fastapi import HTTPException

    with connect(settings) as conn:
        with pytest.raises(HTTPException) as exc:
            get_sensor("DOES-NOT-EXIST", conn=conn)
    assert exc.value.status_code == 404


def test_simulator_tick_writes_reading_and_updates_sensor(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    initialize_database(settings)
    broadcaster = _RecordingBroadcaster()
    simulator = GasSimulator(settings, broadcaster)

    asyncio.run(simulator._tick())

    with connect(settings) as conn:
        reading_count = conn.execute("SELECT COUNT(*) FROM gas_readings").fetchone()[0]
        sensor = conn.execute(
            "SELECT last_reading, last_updated FROM gas_sensors WHERE id = 'GS-001'"
        ).fetchone()

    assert reading_count == EXPECTED_SENSOR_COUNT
    assert sensor["last_reading"] is not None
    assert sensor["last_updated"] is not None
    assert any(event == "gas:reading_update" for event, _ in broadcaster.events)


def test_simulator_opens_and_resolves_alert_on_spike_then_normal(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    initialize_database(settings)
    broadcaster = _RecordingBroadcaster()
    simulator = GasSimulator(settings, broadcaster)

    simulator._spike = {
        "sensor_id": "GS-001",
        "sensor_type": "CH4",
        "severity": "critical",
        "remaining": 1,
    }
    asyncio.run(simulator._tick())

    with connect(settings) as conn:
        sensor = conn.execute(
            "SELECT status FROM gas_sensors WHERE id = 'GS-001'"
        ).fetchone()
        active_alerts = conn.execute(
            "SELECT COUNT(*) FROM gas_alerts WHERE sensor_id = 'GS-001' AND resolved_at IS NULL"
        ).fetchone()[0]
    assert sensor["status"] == "alert"
    assert active_alerts == 1
    assert any(event == "gas:alert" for event, _ in broadcaster.events)

    broadcaster.events.clear()
    simulator._spike = None
    asyncio.run(simulator._tick())

    with connect(settings) as conn:
        sensor = conn.execute(
            "SELECT status FROM gas_sensors WHERE id = 'GS-001'"
        ).fetchone()
        active_alerts = conn.execute(
            "SELECT COUNT(*) FROM gas_alerts WHERE sensor_id = 'GS-001' AND resolved_at IS NULL"
        ).fetchone()[0]
    assert sensor["status"] == "online"
    assert active_alerts == 0
    assert any(event == "gas:resolved" for event, _ in broadcaster.events)


def test_summary_counts_match_seed(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    initialize_database(settings)
    with connect(settings) as conn:
        result = summary(conn=conn)
    assert result["total"] == EXPECTED_SENSOR_COUNT
    assert result["online"] == EXPECTED_SENSOR_COUNT
    assert result["inAlert"] == 0
    assert result["activeAlerts"] == 0
    assert result["devices"] == 0
    assert result["buildings"] >= 5
    assert "readings24h" in result


def test_buildings_endpoint_returns_grouped_sensors(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    initialize_database(settings)
    with connect(settings) as conn:
        result = list_buildings(conn=conn)
    assert len(result["buildings"]) >= 5
    titan = next(b for b in result["buildings"] if b["buildingId"] == "BLD-TITAN")
    assert titan["sensorCount"] >= 3
    assert titan["status"] in ("online", "alert", "offline")


def test_register_device_and_heartbeat(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    initialize_database(settings)
    with connect(settings) as conn:
        device = asyncio.run(
            register_device(
                RegisterDeviceRequest(
                    device_id="dev-aaa",
                    label="Phone A",
                    platform="android",
                    owner="Tech Crew",
                ),
                conn=conn,
            )
        )
        listed = list_devices(conn=conn)
    assert device["deviceId"] == "dev-aaa"
    assert device["label"] == "Phone A"
    assert any(d["deviceId"] == "dev-aaa" for d in listed["devices"])


def test_register_device_is_idempotent_and_updates_label(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    initialize_database(settings)
    with connect(settings) as conn:
        asyncio.run(
            register_device(
                RegisterDeviceRequest(device_id="dev-z", label="Initial"),
                conn=conn,
            )
        )
        updated = asyncio.run(
            register_device(
                RegisterDeviceRequest(device_id="dev-z", label="Renamed"),
                conn=conn,
            )
        )
        count = conn.execute(
            "SELECT COUNT(*) FROM gas_devices WHERE device_id = 'dev-z'"
        ).fetchone()[0]
    assert updated["label"] == "Renamed"
    assert count == 1


def test_ack_alert_records_acknowledgement(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    initialize_database(settings)
    broadcaster = _RecordingBroadcaster()
    simulator = GasSimulator(settings, broadcaster)
    simulator._spike = {
        "sensor_id": "GS-001",
        "sensor_type": "CH4",
        "severity": "warning",
        "remaining": 1,
    }
    asyncio.run(simulator._tick())

    with connect(settings) as conn:
        alert_row = conn.execute(
            "SELECT id FROM gas_alerts WHERE sensor_id = 'GS-001' ORDER BY id DESC LIMIT 1"
        ).fetchone()
        asyncio.run(
            register_device(
                RegisterDeviceRequest(device_id="dev-phone-1", label="Phone 1"),
                conn=conn,
            )
        )
        asyncio.run(
            register_device(
                RegisterDeviceRequest(device_id="dev-phone-2", label="Phone 2"),
                conn=conn,
            )
        )
        ack1 = asyncio.run(
            ack_alert(
                alert_id=alert_row["id"],
                request=AckAlertRequest(device_id="dev-phone-1"),
                conn=conn,
            )
        )
        ack2 = asyncio.run(
            ack_alert(
                alert_id=alert_row["id"],
                request=AckAlertRequest(device_id="dev-phone-2"),
                conn=conn,
            )
        )
        acks = list_acks(alert_id=alert_row["id"], conn=conn)

    assert ack1["ackCount"] == 1
    assert ack2["ackCount"] == 2
    assert ack2["deviceCount"] == 2
    assert len(acks["acks"]) == 2


def test_ack_alert_duplicate_call_is_idempotent(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    initialize_database(settings)
    broadcaster = _RecordingBroadcaster()
    simulator = GasSimulator(settings, broadcaster)
    simulator._spike = {
        "sensor_id": "GS-002",
        "sensor_type": "CO",
        "severity": "warning",
        "remaining": 1,
    }
    asyncio.run(simulator._tick())

    with connect(settings) as conn:
        alert_row = conn.execute(
            "SELECT id FROM gas_alerts WHERE sensor_id = 'GS-002' ORDER BY id DESC LIMIT 1"
        ).fetchone()
        asyncio.run(
            register_device(
                RegisterDeviceRequest(device_id="dev-x", label="Phone X"),
                conn=conn,
            )
        )
        asyncio.run(
            ack_alert(
                alert_id=alert_row["id"],
                request=AckAlertRequest(device_id="dev-x"),
                conn=conn,
            )
        )
        asyncio.run(
            ack_alert(
                alert_id=alert_row["id"],
                request=AckAlertRequest(device_id="dev-x"),
                conn=conn,
            )
        )
        count = conn.execute(
            "SELECT COUNT(*) FROM gas_alert_acks WHERE alert_id = ?",
            (alert_row["id"],),
        ).fetchone()[0]
    assert count == 1


def test_ack_unknown_device_404s(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    initialize_database(settings)
    from fastapi import HTTPException

    with connect(settings) as conn:
        with pytest.raises(HTTPException) as exc:
            asyncio.run(
                ack_alert(
                    alert_id=999_999,
                    request=AckAlertRequest(device_id="nope"),
                    conn=conn,
                )
            )
    assert exc.value.status_code == 404


def test_get_readings_returns_history(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    initialize_database(settings)
    broadcaster = _RecordingBroadcaster()
    simulator = GasSimulator(settings, broadcaster)
    asyncio.run(simulator._tick())
    asyncio.run(simulator._tick())

    with connect(settings) as conn:
        result = get_readings("GS-001", limit=10, conn=conn)
    assert result["sensorId"] == "GS-001"
    assert len(result["readings"]) == 2


def test_manual_resolve_clears_alert(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    initialize_database(settings)
    broadcaster = _RecordingBroadcaster()
    simulator = GasSimulator(settings, broadcaster)
    simulator._spike = {
        "sensor_id": "GS-001",
        "sensor_type": "CH4",
        "severity": "warning",
        "remaining": 1,
    }
    asyncio.run(simulator._tick())

    with connect(settings) as conn:
        alert_row = conn.execute(
            "SELECT id FROM gas_alerts WHERE sensor_id = 'GS-001' ORDER BY id DESC LIMIT 1"
        ).fetchone()
        asyncio.run(resolve_alert(alert_id=alert_row["id"], conn=conn))
        resolved = conn.execute(
            "SELECT resolved_at, resolved_by FROM gas_alerts WHERE id = ?",
            (alert_row["id"],),
        ).fetchone()

    assert resolved["resolved_at"] is not None
    assert resolved["resolved_by"] == "manual"


def test_ingest_stub_accepts_reading(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    initialize_database(settings)
    with connect(settings) as conn:
        response = asyncio.run(
            ingest_reading(
                IngestReadingRequest(sensor_id="GS-002", value_ppm=12.5),
                conn=conn,
            )
        )
        row = conn.execute(
            "SELECT * FROM gas_readings WHERE sensor_id = 'GS-002'"
        ).fetchone()

    assert response["accepted"] is True
    assert response["status"] == "normal"
    assert row["value_ppm"] == 12.5


def test_list_alerts_active_filter(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    initialize_database(settings)
    broadcaster = _RecordingBroadcaster()
    simulator = GasSimulator(settings, broadcaster)
    simulator._spike = {
        "sensor_id": "GS-003",
        "sensor_type": "MULTI",
        "severity": "warning",
        "remaining": 1,
    }
    asyncio.run(simulator._tick())

    with connect(settings) as conn:
        active = list_alerts(active=True, conn=conn)
        resolved_only = list_alerts(active=False, conn=conn)

    assert len(active["alerts"]) >= 1
    assert all(a["resolvedAt"] is None for a in active["alerts"])
    assert all(a["resolvedAt"] is not None for a in resolved_only["alerts"])


def test_gas_routes_registered_on_app() -> None:
    from app.main import app

    paths = {route.path for route in app.routes}
    assert "/api/v1/gas/sensors" in paths
    assert "/api/v1/gas/sensors/{sensor_id}" in paths
    assert "/api/v1/gas/sensors/{sensor_id}/readings" in paths
    assert "/api/v1/gas/alerts" in paths
    assert "/api/v1/gas/alerts/{alert_id}/resolve" in paths
    assert "/api/v1/gas/summary" in paths
    assert "/api/v1/gas/buildings" in paths
    assert "/api/v1/gas/devices" in paths
    assert "/api/v1/gas/devices/{device_id}/heartbeat" in paths
    assert "/api/v1/gas/alerts/{alert_id}/ack" in paths
    assert "/api/v1/gas/alerts/{alert_id}/acks" in paths
    assert "/api/v1/gas/readings/ingest" in paths
