from __future__ import annotations

import sqlite3
from typing import Any, Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app.gas import (
    THRESHOLDS,
    alert_to_dict,
    classify,
    get_simulator,
    reading_to_dict,
    sensor_to_dict,
    thresholds_for,
)
from app.database import utc_now_iso
from app.hydralis import db, manager

router = APIRouter(prefix="/api/v1/gas", tags=["Gas Monitoring"])


GasSensorType = Literal["CH4", "CO", "LPG", "MULTI"]


class IngestReadingRequest(BaseModel):
    sensor_id: str = Field(..., min_length=1)
    value_ppm: float = Field(..., ge=0)
    timestamp: str | None = None


class RegisterDeviceRequest(BaseModel):
    device_id: str = Field(..., min_length=4, max_length=128)
    label: str = Field(..., min_length=1, max_length=80)
    platform: str | None = Field(default=None, max_length=32)
    owner: str | None = Field(default=None, max_length=120)


class AckAlertRequest(BaseModel):
    device_id: str = Field(..., min_length=4, max_length=128)


class DemoSpikeRequest(BaseModel):
    sensor_id: str = Field(..., min_length=1)
    severity: Literal["warning", "critical"] = Field(default="critical")
    duration_cycles: int | None = Field(default=None, ge=1, le=20)


@router.get("/sensors")
def list_sensors(conn: sqlite3.Connection = Depends(db)) -> dict[str, Any]:
    rows = conn.execute(
        "SELECT * FROM gas_sensors ORDER BY building_id, id"
    ).fetchall()
    sensors = [sensor_to_dict(row) for row in rows]
    return {"sensors": sensors, "thresholds": _thresholds_payload()}


@router.get("/sensors/{sensor_id}")
def get_sensor(sensor_id: str, conn: sqlite3.Connection = Depends(db)) -> dict[str, Any]:
    row = _require_sensor(conn, sensor_id)
    return sensor_to_dict(row)


@router.get("/sensors/{sensor_id}/readings")
def get_readings(
    sensor_id: str,
    limit: int = Query(100, ge=1, le=1000),
    conn: sqlite3.Connection = Depends(db),
) -> dict[str, Any]:
    _require_sensor(conn, sensor_id)
    rows = conn.execute(
        """
        SELECT * FROM gas_readings
        WHERE sensor_id = ?
        ORDER BY id DESC LIMIT ?
        """,
        (sensor_id, limit),
    ).fetchall()
    readings = [reading_to_dict(row) for row in rows]
    readings.reverse()
    return {"sensorId": sensor_id, "readings": readings}


@router.get("/alerts")
def list_alerts(
    active: bool | None = Query(None),
    conn: sqlite3.Connection = Depends(db),
) -> dict[str, Any]:
    sql = "SELECT * FROM gas_alerts"
    params: list[Any] = []
    if active is True:
        sql += " WHERE resolved_at IS NULL"
    elif active is False:
        sql += " WHERE resolved_at IS NOT NULL"
    sql += " ORDER BY triggered_at DESC"
    rows = conn.execute(sql, params).fetchall()
    return {"alerts": [alert_to_dict(row) for row in rows]}


@router.post("/alerts/{alert_id}/resolve")
async def resolve_alert(
    alert_id: int,
    conn: sqlite3.Connection = Depends(db),
) -> dict[str, Any]:
    row = conn.execute(
        "SELECT * FROM gas_alerts WHERE id = ?", (alert_id,)
    ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Gas alert not found")
    if row["resolved_at"] is not None:
        return alert_to_dict(row)
    now = utc_now_iso()
    conn.execute(
        "UPDATE gas_alerts SET resolved_at = ?, resolved_by = ? WHERE id = ?",
        (now, "manual", alert_id),
    )
    conn.execute(
        "UPDATE gas_sensors SET status = 'online' WHERE id = ? AND status = 'alert'",
        (row["sensor_id"],),
    )
    conn.commit()
    updated = conn.execute(
        "SELECT * FROM gas_alerts WHERE id = ?", (alert_id,)
    ).fetchone()
    payload = alert_to_dict(updated)
    await manager.broadcast(
        "gas:resolved",
        {
            "id": alert_id,
            "sensorId": row["sensor_id"],
            "resolvedAt": now,
            "resolvedBy": "manual",
        },
    )
    return payload


@router.get("/summary")
def summary(conn: sqlite3.Connection = Depends(db)) -> dict[str, Any]:
    status_rows = conn.execute(
        "SELECT status, COUNT(*) AS count FROM gas_sensors GROUP BY status"
    ).fetchall()
    counts = {"online": 0, "offline": 0, "alert": 0}
    for row in status_rows:
        counts[row["status"]] = row["count"]
    total = sum(counts.values())
    active_alerts = conn.execute(
        "SELECT COUNT(*) AS n FROM gas_alerts WHERE resolved_at IS NULL"
    ).fetchone()["n"]
    devices = conn.execute(
        "SELECT COUNT(*) AS n FROM gas_devices WHERE status = 'active'"
    ).fetchone()["n"]
    buildings = conn.execute(
        "SELECT COUNT(DISTINCT building_id) AS n FROM gas_sensors"
    ).fetchone()["n"]
    readings_24h = conn.execute(
        "SELECT COUNT(*) AS n FROM gas_readings WHERE timestamp >= ?",
        (_iso_minus_hours(24),),
    ).fetchone()["n"]
    return {
        "total": total,
        "online": counts["online"],
        "offline": counts["offline"],
        "inAlert": counts["alert"],
        "activeAlerts": active_alerts,
        "devices": devices,
        "buildings": buildings,
        "readings24h": readings_24h,
    }


@router.get("/buildings")
def list_buildings(conn: sqlite3.Connection = Depends(db)) -> dict[str, Any]:
    rows = conn.execute(
        """
        SELECT building_id,
               COUNT(*) AS sensor_count,
               SUM(CASE WHEN status = 'alert' THEN 1 ELSE 0 END) AS alert_count,
               SUM(CASE WHEN status = 'online' THEN 1 ELSE 0 END) AS online_count,
               SUM(CASE WHEN status = 'offline' THEN 1 ELSE 0 END) AS offline_count,
               MIN(location_name) AS location_name,
               AVG(latitude) AS latitude,
               AVG(longitude) AS longitude
        FROM gas_sensors
        GROUP BY building_id
        ORDER BY building_id
        """
    ).fetchall()
    return {
        "buildings": [
            {
                "buildingId": row["building_id"],
                "locationName": row["location_name"],
                "latitude": row["latitude"],
                "longitude": row["longitude"],
                "sensorCount": row["sensor_count"],
                "alertCount": row["alert_count"] or 0,
                "onlineCount": row["online_count"] or 0,
                "offlineCount": row["offline_count"] or 0,
                "status": _building_status(row),
            }
            for row in rows
        ]
    }


@router.get("/devices")
def list_devices(conn: sqlite3.Connection = Depends(db)) -> dict[str, Any]:
    rows = conn.execute(
        "SELECT * FROM gas_devices ORDER BY registered_at DESC"
    ).fetchall()
    return {"devices": [_device_to_dict(row) for row in rows]}


@router.post("/devices", status_code=201)
async def register_device(
    request: RegisterDeviceRequest,
    conn: sqlite3.Connection = Depends(db),
) -> dict[str, Any]:
    now = utc_now_iso()
    existing = conn.execute(
        "SELECT * FROM gas_devices WHERE device_id = ?", (request.device_id,)
    ).fetchone()
    if existing is None:
        conn.execute(
            """
            INSERT INTO gas_devices (
                device_id, label, platform, owner, registered_at, last_seen_at, status
            ) VALUES (?, ?, ?, ?, ?, ?, 'active')
            """,
            (
                request.device_id,
                request.label,
                request.platform,
                request.owner,
                now,
                now,
            ),
        )
    else:
        conn.execute(
            """
            UPDATE gas_devices
            SET label = ?, platform = ?, owner = ?, last_seen_at = ?, status = 'active'
            WHERE device_id = ?
            """,
            (
                request.label,
                request.platform,
                request.owner,
                now,
                request.device_id,
            ),
        )
    conn.commit()
    device = conn.execute(
        "SELECT * FROM gas_devices WHERE device_id = ?", (request.device_id,)
    ).fetchone()
    payload = _device_to_dict(device)
    await manager.broadcast("gas:device_registered", payload)
    return payload


@router.post("/devices/{device_id}/heartbeat")
def device_heartbeat(
    device_id: str,
    conn: sqlite3.Connection = Depends(db),
) -> dict[str, Any]:
    now = utc_now_iso()
    result = conn.execute(
        "UPDATE gas_devices SET last_seen_at = ?, status = 'active' WHERE device_id = ?",
        (now, device_id),
    )
    if result.rowcount == 0:
        raise HTTPException(status_code=404, detail="Device not registered")
    conn.commit()
    return {"deviceId": device_id, "lastSeenAt": now}


@router.post("/alerts/{alert_id}/ack")
async def ack_alert(
    alert_id: int,
    request: AckAlertRequest,
    conn: sqlite3.Connection = Depends(db),
) -> dict[str, Any]:
    alert_row = conn.execute(
        "SELECT * FROM gas_alerts WHERE id = ?", (alert_id,)
    ).fetchone()
    if alert_row is None:
        raise HTTPException(status_code=404, detail="Gas alert not found")
    device_row = conn.execute(
        "SELECT * FROM gas_devices WHERE device_id = ?", (request.device_id,)
    ).fetchone()
    if device_row is None:
        raise HTTPException(status_code=404, detail="Device not registered")
    now = utc_now_iso()
    conn.execute(
        """
        INSERT OR IGNORE INTO gas_alert_acks (alert_id, device_id, acknowledged_at)
        VALUES (?, ?, ?)
        """,
        (alert_id, request.device_id, now),
    )
    conn.execute(
        "UPDATE gas_devices SET last_seen_at = ? WHERE device_id = ?",
        (now, request.device_id),
    )
    conn.commit()
    ack_count = conn.execute(
        "SELECT COUNT(*) AS n FROM gas_alert_acks WHERE alert_id = ?",
        (alert_id,),
    ).fetchone()["n"]
    device_count = conn.execute(
        "SELECT COUNT(*) AS n FROM gas_devices WHERE status = 'active'"
    ).fetchone()["n"]
    payload = {
        "alertId": alert_id,
        "deviceId": request.device_id,
        "deviceLabel": device_row["label"],
        "acknowledgedAt": now,
        "ackCount": ack_count,
        "deviceCount": device_count,
    }
    await manager.broadcast("gas:alert_ack", payload)
    return payload


@router.get("/alerts/{alert_id}/acks")
def list_acks(
    alert_id: int,
    conn: sqlite3.Connection = Depends(db),
) -> dict[str, Any]:
    rows = conn.execute(
        """
        SELECT a.alert_id, a.device_id, a.acknowledged_at,
               d.label, d.platform, d.owner
        FROM gas_alert_acks a
        LEFT JOIN gas_devices d ON d.device_id = a.device_id
        WHERE a.alert_id = ?
        ORDER BY a.acknowledged_at DESC
        """,
        (alert_id,),
    ).fetchall()
    return {
        "alertId": alert_id,
        "acks": [
            {
                "deviceId": row["device_id"],
                "deviceLabel": row["label"],
                "platform": row["platform"],
                "owner": row["owner"],
                "acknowledgedAt": row["acknowledged_at"],
            }
            for row in rows
        ],
    }


@router.post("/demo/spike", status_code=202)
async def demo_spike(
    request: DemoSpikeRequest,
    conn: sqlite3.Connection = Depends(db),
) -> dict[str, Any]:
    """Force a deterministic gas alarm for demos.

    Lets the dispatcher dashboard send a *specific* alarm (sensor + severity)
    instead of waiting for the random simulator. Reuses the existing simulator
    pipeline so the resulting ``gas:alert`` looks identical to a natural spike
    on every connected client (mobile + web).
    """
    sensor = _require_sensor(conn, request.sensor_id)
    simulator = get_simulator(manager)
    simulator.force_spike(
        sensor["id"],
        severity=request.severity,
        duration_cycles=request.duration_cycles,
    )
    return {
        "scheduled": True,
        "sensorId": sensor["id"],
        "sensorType": sensor["sensor_type"],
        "severity": request.severity,
        "durationCycles": request.duration_cycles,
    }


@router.post("/demo/clear", status_code=202)
async def demo_clear() -> dict[str, Any]:
    simulator = get_simulator(manager)
    simulator.clear_spike()
    return {"cleared": True}


@router.post("/readings/ingest", status_code=202)
async def ingest_reading(
    request: IngestReadingRequest,
    conn: sqlite3.Connection = Depends(db),
) -> dict[str, Any]:
    sensor = _require_sensor(conn, request.sensor_id)
    sensor_type = sensor["sensor_type"]
    now = request.timestamp or utc_now_iso()
    status = classify(sensor_type, request.value_ppm)
    conn.execute(
        """
        INSERT INTO gas_readings (sensor_id, sensor_type, value_ppm, status, timestamp)
        VALUES (?, ?, ?, ?, ?)
        """,
        (sensor["id"], sensor_type, request.value_ppm, status, now),
    )
    new_status = "alert" if status in ("warning", "critical") else "online"
    conn.execute(
        "UPDATE gas_sensors SET last_reading = ?, last_updated = ?, status = ? WHERE id = ?",
        (request.value_ppm, now, new_status, sensor["id"]),
    )
    conn.commit()
    return {
        "accepted": True,
        "sensorId": sensor["id"],
        "status": status,
        "timestamp": now,
    }


def _require_sensor(conn: sqlite3.Connection, sensor_id: str) -> sqlite3.Row:
    row = conn.execute(
        "SELECT * FROM gas_sensors WHERE id = ?", (sensor_id,)
    ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Gas sensor not found")
    return row


def _thresholds_payload() -> dict[str, dict[str, float]]:
    return {
        sensor_type: {
            "warning": values.warning,
            "critical": values.critical,
        }
        for sensor_type, values in THRESHOLDS.items()
    }


def _device_to_dict(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "deviceId": row["device_id"],
        "label": row["label"],
        "platform": row["platform"],
        "owner": row["owner"],
        "registeredAt": row["registered_at"],
        "lastSeenAt": row["last_seen_at"],
        "status": row["status"],
    }


def _building_status(row: sqlite3.Row) -> str:
    if (row["alert_count"] or 0) > 0:
        return "alert"
    if (row["offline_count"] or 0) >= (row["sensor_count"] or 1):
        return "offline"
    return "online"


def _iso_minus_hours(hours: int) -> str:
    from datetime import datetime, timedelta, timezone

    point = datetime.now(timezone.utc) - timedelta(hours=hours)
    return point.replace(microsecond=0).isoformat().replace("+00:00", "Z")
