from __future__ import annotations

import asyncio
import logging
import random
import sqlite3
from dataclasses import dataclass
from typing import Any, Literal

from app.config import Settings, get_settings
from app.database import connect, utc_now_iso


logger = logging.getLogger(__name__)


SensorType = Literal["CH4", "CO", "LPG", "MULTI"]
ReadingStatus = Literal["normal", "warning", "critical"]


SIMULATION_INTERVAL_SECONDS = 15
SPIKE_INTERVAL_SECONDS = 90
SPIKE_DURATION_CYCLES_MIN = 2
SPIKE_DURATION_CYCLES_MAX = 3


@dataclass(frozen=True)
class Thresholds:
    warning: float
    critical: float


THRESHOLDS: dict[str, Thresholds] = {
    "CH4": Thresholds(warning=1000.0, critical=5000.0),
    "CO": Thresholds(warning=35.0, critical=200.0),
    "LPG": Thresholds(warning=1000.0, critical=5000.0),
    "MULTI": Thresholds(warning=1000.0, critical=5000.0),
}


BASE_READINGS: dict[str, float] = {
    "CH4": 200.0,
    "CO": 8.0,
    "LPG": 150.0,
    "MULTI": 200.0,
}


NOISE_FRACTION = 0.08


def thresholds_for(sensor_type: str) -> Thresholds:
    return THRESHOLDS.get(sensor_type, THRESHOLDS["CH4"])


def base_value_for(sensor_type: str) -> float:
    return BASE_READINGS.get(sensor_type, BASE_READINGS["CH4"])


def classify(sensor_type: str, value_ppm: float) -> ReadingStatus:
    th = thresholds_for(sensor_type)
    if value_ppm >= th.critical:
        return "critical"
    if value_ppm >= th.warning:
        return "warning"
    return "normal"


def sensor_to_dict(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "name": row["name"],
        "locationName": row["location_name"],
        "latitude": row["latitude"],
        "longitude": row["longitude"],
        "floor": row["floor"],
        "sensorType": row["sensor_type"],
        "status": row["status"],
        "lastReading": row["last_reading"],
        "lastUpdated": row["last_updated"],
        "buildingId": row["building_id"],
    }


def reading_to_dict(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "sensorId": row["sensor_id"],
        "sensorType": row["sensor_type"],
        "valuePpm": row["value_ppm"],
        "status": row["status"],
        "timestamp": row["timestamp"],
    }


def alert_to_dict(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "sensorId": row["sensor_id"],
        "sensorType": row["sensor_type"],
        "valuePpm": row["value_ppm"],
        "threshold": row["threshold"],
        "location": row["location"],
        "triggeredAt": row["triggered_at"],
        "resolvedAt": row["resolved_at"],
        "resolvedBy": row["resolved_by"],
    }


class GasSimulator:
    """
    Background task generating realistic gas sensor readings. Periodically spikes
    a random sensor into warning or critical range and lets it recover.
    """

    def __init__(self, settings: Settings, broadcaster: Any) -> None:
        self._settings = settings
        self._broadcaster = broadcaster
        self._task: asyncio.Task[None] | None = None
        self._stop_event = asyncio.Event()
        self._spike: dict[str, Any] | None = None
        self._cycles_since_spike = 0

    @property
    def is_running(self) -> bool:
        return self._task is not None and not self._task.done()

    def start(self) -> None:
        if self.is_running:
            return
        self._stop_event.clear()
        self._task = asyncio.create_task(self._run(), name="gas-simulator")
        logger.info("Gas simulator started (interval=%ss)", SIMULATION_INTERVAL_SECONDS)

    async def stop(self) -> None:
        if self._task is None:
            return
        self._stop_event.set()
        try:
            await asyncio.wait_for(self._task, timeout=5.0)
        except (asyncio.TimeoutError, asyncio.CancelledError):
            self._task.cancel()
        self._task = None
        logger.info("Gas simulator stopped")

    async def _run(self) -> None:
        try:
            while not self._stop_event.is_set():
                try:
                    await self._tick()
                except Exception:
                    logger.exception("Gas simulator tick failed")
                try:
                    await asyncio.wait_for(
                        self._stop_event.wait(), timeout=SIMULATION_INTERVAL_SECONDS
                    )
                except asyncio.TimeoutError:
                    continue
        except asyncio.CancelledError:
            pass

    async def _tick(self) -> None:
        self._cycles_since_spike += SIMULATION_INTERVAL_SECONDS
        if self._spike is not None and self._spike["remaining"] <= 0:
            self._spike = None

        conn = connect(self._settings)
        try:
            sensors = conn.execute(
                "SELECT * FROM gas_sensors ORDER BY id"
            ).fetchall()
            if not sensors:
                return

            spike_target_id = self._maybe_pick_spike(sensors)
            updates: list[dict[str, Any]] = []
            alerts_triggered: list[dict[str, Any]] = []
            alerts_resolved: list[dict[str, Any]] = []
            now = utc_now_iso()

            for sensor_row in sensors:
                sensor = sensor_to_dict(sensor_row)
                value = self._next_value(sensor, spike_target_id)
                status = classify(sensor["sensorType"], value)
                self._save_reading(conn, sensor, value, status, now)

                prev_status = sensor["status"]
                new_status = "alert" if status in ("warning", "critical") else "online"
                conn.execute(
                    "UPDATE gas_sensors SET last_reading = ?, last_updated = ?, status = ? WHERE id = ?",
                    (value, now, new_status, sensor["id"]),
                )

                if status in ("warning", "critical") and prev_status != "alert":
                    alert = self._open_alert(conn, sensor, value, status, now)
                    alerts_triggered.append(alert)
                elif status == "normal" and prev_status == "alert":
                    resolved = self._auto_resolve(conn, sensor["id"], now)
                    if resolved is not None:
                        alerts_resolved.append(resolved)

                updates.append(
                    {
                        "sensorId": sensor["id"],
                        "sensorType": sensor["sensorType"],
                        "valuePpm": value,
                        "status": status,
                        "sensorStatus": new_status,
                        "locationName": sensor["locationName"],
                        "timestamp": now,
                    }
                )

            conn.commit()
        finally:
            conn.close()

        if self._broadcaster is not None:
            await self._broadcaster.broadcast(
                "gas:reading_update", {"readings": updates, "timestamp": now}
            )
            for alert_payload in alerts_triggered:
                await self._broadcaster.broadcast("gas:alert", alert_payload)
            for resolved_payload in alerts_resolved:
                await self._broadcaster.broadcast("gas:resolved", resolved_payload)

    def _maybe_pick_spike(self, sensors: list[sqlite3.Row]) -> str | None:
        if self._spike is not None:
            self._spike["remaining"] -= 1
            return self._spike["sensor_id"]

        if self._cycles_since_spike < SPIKE_INTERVAL_SECONDS:
            return None
        self._cycles_since_spike = 0
        if random.random() > 0.85:
            return None
        target_row = random.choice(sensors)
        duration = random.randint(
            SPIKE_DURATION_CYCLES_MIN, SPIKE_DURATION_CYCLES_MAX
        )
        severity = random.choice(("warning", "critical"))
        self._spike = {
            "sensor_id": target_row["id"],
            "sensor_type": target_row["sensor_type"],
            "severity": severity,
            "remaining": duration,
        }
        logger.info(
            "Gas simulator spiking sensor %s (%s) %s for %d cycles",
            target_row["id"],
            target_row["sensor_type"],
            severity,
            duration,
        )
        return target_row["id"]

    def _next_value(self, sensor: dict[str, Any], spike_target_id: str | None) -> float:
        sensor_type = sensor["sensorType"]
        if (
            self._spike is not None
            and spike_target_id == sensor["id"]
            and sensor["id"] == self._spike["sensor_id"]
        ):
            th = thresholds_for(sensor_type)
            if self._spike["severity"] == "critical":
                base = th.critical * random.uniform(1.05, 1.30)
            else:
                base = th.warning * random.uniform(1.05, 1.40)
            jitter = base * NOISE_FRACTION * random.gauss(0, 1)
            return max(0.0, round(base + jitter, 2))

        base = base_value_for(sensor_type)
        jitter = base * NOISE_FRACTION * random.gauss(0, 1)
        return max(0.0, round(base + jitter, 2))

    def _save_reading(
        self,
        conn: sqlite3.Connection,
        sensor: dict[str, Any],
        value: float,
        status: ReadingStatus,
        now: str,
    ) -> None:
        conn.execute(
            """
            INSERT INTO gas_readings (sensor_id, sensor_type, value_ppm, status, timestamp)
            VALUES (?, ?, ?, ?, ?)
            """,
            (sensor["id"], sensor["sensorType"], value, status, now),
        )

    def _open_alert(
        self,
        conn: sqlite3.Connection,
        sensor: dict[str, Any],
        value: float,
        status: ReadingStatus,
        now: str,
    ) -> dict[str, Any]:
        th = thresholds_for(sensor["sensorType"])
        threshold = th.critical if status == "critical" else th.warning
        cursor = conn.execute(
            """
            INSERT INTO gas_alerts (
                sensor_id, sensor_type, value_ppm, threshold, location, triggered_at
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                sensor["id"],
                sensor["sensorType"],
                value,
                threshold,
                sensor["locationName"],
                now,
            ),
        )
        alert_id = cursor.lastrowid
        device_count = conn.execute(
            "SELECT COUNT(*) AS n FROM gas_devices WHERE status = 'active'"
        ).fetchone()["n"]
        return {
            "id": alert_id,
            "sensorId": sensor["id"],
            "sensorType": sensor["sensorType"],
            "valuePpm": value,
            "threshold": threshold,
            "locationName": sensor["locationName"],
            "status": status,
            "triggeredAt": now,
            "deviceCount": device_count,
            "ackCount": 0,
        }

    def _auto_resolve(
        self, conn: sqlite3.Connection, sensor_id: str, now: str
    ) -> dict[str, Any] | None:
        row = conn.execute(
            """
            SELECT id FROM gas_alerts
            WHERE sensor_id = ? AND resolved_at IS NULL
            ORDER BY id DESC LIMIT 1
            """,
            (sensor_id,),
        ).fetchone()
        if row is None:
            return None
        conn.execute(
            "UPDATE gas_alerts SET resolved_at = ?, resolved_by = ? WHERE id = ?",
            (now, "auto", row["id"]),
        )
        return {
            "id": row["id"],
            "sensorId": sensor_id,
            "resolvedAt": now,
            "resolvedBy": "auto",
        }


_simulator: GasSimulator | None = None


def get_simulator(broadcaster: Any | None = None) -> GasSimulator:
    global _simulator
    if _simulator is None:
        _simulator = GasSimulator(get_settings(), broadcaster)
    return _simulator


def set_simulator(simulator: GasSimulator | None) -> None:
    global _simulator
    _simulator = simulator
