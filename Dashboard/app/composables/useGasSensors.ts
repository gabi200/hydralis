export type GasSensorType = "CH4" | "CO" | "LPG" | "MULTI";
export type GasSensorStatus = "online" | "offline" | "alert";
export type GasReadingStatus = "normal" | "warning" | "critical";

export interface GasSensor {
  id: string;
  name: string;
  locationName: string;
  latitude: number;
  longitude: number;
  floor: number;
  sensorType: GasSensorType;
  status: GasSensorStatus;
  lastReading: number | null;
  lastUpdated: string | null;
  buildingId: string | null;
}

export interface GasReading {
  id: number;
  sensorId: string;
  sensorType: GasSensorType;
  valuePpm: number;
  status: GasReadingStatus;
  timestamp: string;
}

export interface GasAlert {
  id: number;
  sensorId: string;
  sensorType: GasSensorType;
  valuePpm: number;
  threshold: number;
  location: string;
  triggeredAt: string;
  resolvedAt: string | null;
  resolvedBy: string | null;
}

export interface GasThresholds {
  warning: number;
  critical: number;
}

interface SensorsResponse {
  sensors: GasSensor[];
  thresholds: Record<GasSensorType, GasThresholds>;
}

interface AlertsResponse {
  alerts: GasAlert[];
}

interface ReadingsResponse {
  sensorId: string;
  readings: GasReading[];
}

interface SummaryResponse {
  total: number;
  online: number;
  offline: number;
  inAlert: number;
  activeAlerts: number;
  devices?: number;
  buildings?: number;
  readings24h?: number;
}

export interface GasBuilding {
  buildingId: string;
  locationName: string;
  latitude: number;
  longitude: number;
  sensorCount: number;
  alertCount: number;
  onlineCount: number;
  offlineCount: number;
  status: "online" | "alert" | "offline";
}

export interface GasDevice {
  deviceId: string;
  label: string;
  platform: string | null;
  owner: string | null;
  registeredAt: string;
  lastSeenAt: string | null;
  status: string;
}

export interface GasAck {
  deviceId: string;
  deviceLabel: string | null;
  platform: string | null;
  owner: string | null;
  acknowledgedAt: string;
}

const HISTORY_LIMIT = 10;

const colorForReadingStatus = (status: GasReadingStatus): string => {
  switch (status) {
    case "critical":
      return "#EF4444";
    case "warning":
      return "#F59E0B";
    case "normal":
    default:
      return "#22C55E";
  }
};

const colorForSensor = (sensor: GasSensor): string => {
  if (sensor.status === "offline") return "#6B7280";
  if (sensor.status === "alert") {
    const reading = sensor.lastReading ?? 0;
    const status = classifyReading(sensor.sensorType, reading);
    return colorForReadingStatus(status);
  }
  return "#22C55E";
};

const classifyReading = (
  type: GasSensorType,
  value: number,
  thresholds?: GasThresholds,
): GasReadingStatus => {
  const fallback: Record<GasSensorType, GasThresholds> = {
    CH4: { warning: 1000, critical: 5000 },
    CO: { warning: 35, critical: 200 },
    LPG: { warning: 1000, critical: 5000 },
    MULTI: { warning: 1000, critical: 5000 },
  };
  const th = thresholds ?? fallback[type];
  if (value >= th.critical) return "critical";
  if (value >= th.warning) return "warning";
  return "normal";
};

export const useGasSensors = () => {
  const { get, post } = useApi();

  const sensors = useState<GasSensor[]>("gas-sensors", () => []);
  const thresholds = useState<Record<GasSensorType, GasThresholds>>(
    "gas-thresholds",
    () => ({
      CH4: { warning: 1000, critical: 5000 },
      CO: { warning: 35, critical: 200 },
      LPG: { warning: 1000, critical: 5000 },
      MULTI: { warning: 1000, critical: 5000 },
    }),
  );
  const alerts = useState<GasAlert[]>("gas-alerts", () => []);
  const alertHistory = useState<GasAlert[]>("gas-alert-history", () => []);
  const buildings = useState<GasBuilding[]>("gas-buildings", () => []);
  const devices = useState<GasDevice[]>("gas-devices", () => []);
  const acksByAlert = useState<Record<number, GasAck[]>>(
    "gas-acks-by-alert",
    () => ({}),
  );
  const ackCounts = useState<Record<number, number>>(
    "gas-ack-counts",
    () => ({}),
  );
  const lastSummary = useState<SummaryResponse | null>(
    "gas-summary-response",
    () => null,
  );
  const history = useState<Record<string, number[]>>(
    "gas-readings-history",
    () => ({}),
  );
  const flashStates = useState<Record<string, number>>(
    "gas-flash-states",
    () => ({}),
  );
  const loading = useState("gas-loading", () => false);

  const refreshSensors = async () => {
    try {
      const data = await get<SensorsResponse>("/api/v1/gas/sensors");
      sensors.value = data.sensors;
      thresholds.value = data.thresholds;
      for (const sensor of data.sensors) {
        if (!history.value[sensor.id]) {
          history.value[sensor.id] =
            sensor.lastReading != null ? [sensor.lastReading] : [];
        }
      }
    } catch (err) {
      console.error("[useGasSensors] refreshSensors failed:", err);
    }
  };

  const refreshAlerts = async () => {
    try {
      const data = await get<AlertsResponse>("/api/v1/gas/alerts?active=true");
      alerts.value = data.alerts;
    } catch (err) {
      console.error("[useGasSensors] refreshAlerts failed:", err);
    }
  };

  const refreshAlertHistory = async () => {
    try {
      const data = await get<AlertsResponse>("/api/v1/gas/alerts");
      alertHistory.value = data.alerts;
    } catch (err) {
      console.error("[useGasSensors] refreshAlertHistory failed:", err);
    }
  };

  const refreshBuildings = async () => {
    try {
      const data = await get<{ buildings: GasBuilding[] }>(
        "/api/v1/gas/buildings",
      );
      buildings.value = data.buildings;
    } catch (err) {
      console.error("[useGasSensors] refreshBuildings failed:", err);
    }
  };

  const refreshDevices = async () => {
    try {
      const data = await get<{ devices: GasDevice[] }>("/api/v1/gas/devices");
      devices.value = data.devices;
    } catch (err) {
      console.error("[useGasSensors] refreshDevices failed:", err);
    }
  };

  const fetchAcks = async (alertId: number) => {
    try {
      const data = await get<{ alertId: number; acks: GasAck[] }>(
        `/api/v1/gas/alerts/${alertId}/acks`,
      );
      acksByAlert.value[alertId] = data.acks;
      ackCounts.value[alertId] = data.acks.length;
      return data.acks;
    } catch (err) {
      console.error("[useGasSensors] fetchAcks failed:", err);
      return [];
    }
  };

  const refreshAll = async () => {
    loading.value = true;
    try {
      await Promise.all([
        refreshSensors(),
        refreshAlerts(),
        refreshBuildings(),
        refreshDevices(),
      ]);
    } finally {
      loading.value = false;
    }
  };

  const fetchHistory = async (sensorId: string, limit = 50) => {
    try {
      const data = await get<ReadingsResponse>(
        `/api/v1/gas/sensors/${sensorId}/readings?limit=${limit}`,
      );
      history.value[sensorId] = data.readings.map((r) => r.valuePpm);
      return data.readings;
    } catch (err) {
      console.error("[useGasSensors] fetchHistory failed:", err);
      return [];
    }
  };

  const resolveAlert = async (alertId: number) => {
    await post(`/api/v1/gas/alerts/${alertId}/resolve`);
    await Promise.all([refreshAlerts(), refreshSensors()]);
  };

  const applyReadingUpdate = (payload: {
    readings: Array<{
      sensorId: string;
      sensorType: GasSensorType;
      valuePpm: number;
      status: GasReadingStatus;
      sensorStatus: GasSensorStatus;
      locationName: string;
      timestamp: string;
    }>;
    timestamp: string;
  }) => {
    for (const r of payload.readings) {
      const sensor = sensors.value.find((s) => s.id === r.sensorId);
      if (sensor) {
        sensor.lastReading = r.valuePpm;
        sensor.lastUpdated = r.timestamp;
        sensor.status = r.sensorStatus;
      }
      const prev = history.value[r.sensorId] ?? [];
      const next = [...prev, r.valuePpm];
      if (next.length > HISTORY_LIMIT)
        next.splice(0, next.length - HISTORY_LIMIT);
      history.value[r.sensorId] = next;
    }
  };

  const applyAlert = (payload: {
    id: number;
    sensorId: string;
    sensorType: GasSensorType;
    valuePpm: number;
    threshold: number;
    locationName?: string;
    location?: string;
    triggeredAt: string;
  }) => {
    const newAlert: GasAlert = {
      id: payload.id,
      sensorId: payload.sensorId,
      sensorType: payload.sensorType,
      valuePpm: payload.valuePpm,
      threshold: payload.threshold,
      location: payload.location ?? payload.locationName ?? "",
      triggeredAt: payload.triggeredAt,
      resolvedAt: null,
      resolvedBy: null,
    };
    const exists = alerts.value.some((a) => a.id === newAlert.id);
    if (!exists) {
      alerts.value = [newAlert, ...alerts.value];
      alertHistory.value = [newAlert, ...alertHistory.value];
    }
    ackCounts.value[newAlert.id] = ackCounts.value[newAlert.id] ?? 0;
    flashStates.value[payload.sensorId] = Date.now();
    const sensor = sensors.value.find((s) => s.id === payload.sensorId);
    if (sensor) {
      sensor.status = "alert";
      sensor.lastReading = payload.valuePpm;
    }
  };

  const applyAck = (payload: {
    alertId: number;
    deviceId: string;
    deviceLabel?: string;
    acknowledgedAt: string;
    ackCount: number;
    deviceCount?: number;
  }) => {
    ackCounts.value[payload.alertId] = payload.ackCount;
    const list = acksByAlert.value[payload.alertId] ?? [];
    if (!list.some((a) => a.deviceId === payload.deviceId)) {
      list.unshift({
        deviceId: payload.deviceId,
        deviceLabel: payload.deviceLabel ?? null,
        platform: null,
        owner: null,
        acknowledgedAt: payload.acknowledgedAt,
      });
      acksByAlert.value[payload.alertId] = list;
    }
  };

  const applyDeviceRegistered = (payload: GasDevice) => {
    const idx = devices.value.findIndex((d) => d.deviceId === payload.deviceId);
    if (idx === -1) {
      devices.value = [payload, ...devices.value];
    } else {
      devices.value[idx] = payload;
    }
  };

  const applyResolved = (payload: {
    id?: number;
    sensorId: string;
    resolvedAt: string;
    resolvedBy?: string;
  }) => {
    if (payload.id != null) {
      alerts.value = alerts.value.filter((a) => a.id !== payload.id);
      alertHistory.value = alertHistory.value.map((a) =>
        a.id === payload.id
          ? {
              ...a,
              resolvedAt: payload.resolvedAt,
              resolvedBy: payload.resolvedBy ?? a.resolvedBy,
            }
          : a,
      );
    } else {
      alerts.value = alerts.value.filter(
        (a) => a.sensorId !== payload.sensorId || a.resolvedAt !== null,
      );
    }
    delete flashStates.value[payload.sensorId];
    const sensor = sensors.value.find((s) => s.id === payload.sensorId);
    if (sensor && sensor.status === "alert") {
      sensor.status = "online";
    }
  };

  const summary = computed(() => ({
    total: sensors.value.length,
    online: sensors.value.filter((s) => s.status === "online").length,
    offline: sensors.value.filter((s) => s.status === "offline").length,
    inAlert: sensors.value.filter((s) => s.status === "alert").length,
    activeAlerts: alerts.value.length,
    devices: devices.value.length,
    buildings: buildings.value.length,
    readings24h: lastSummary.value?.readings24h ?? 0,
  }));

  const fetchSummary = async (): Promise<SummaryResponse | null> => {
    try {
      const data = await get<SummaryResponse>("/api/v1/gas/summary");
      lastSummary.value = data;
      return data;
    } catch (err) {
      console.error("[useGasSensors] fetchSummary failed:", err);
      return null;
    }
  };

  const activeAlertCount = computed(() => alerts.value.length);

  if (import.meta.client && sensors.value.length === 0) {
    refreshAll();
    fetchSummary();
    refreshAlertHistory();
  }

  return {
    sensors,
    alerts,
    alertHistory,
    buildings,
    devices,
    history,
    flashStates,
    thresholds,
    acksByAlert,
    ackCounts,
    loading,
    summary,
    activeAlertCount,
    colorForReadingStatus,
    colorForSensor,
    classifyReading,
    refreshSensors,
    refreshAlerts,
    refreshAlertHistory,
    refreshBuildings,
    refreshDevices,
    refreshAll,
    fetchHistory,
    fetchSummary,
    fetchAcks,
    resolveAlert,
    applyReadingUpdate,
    applyAlert,
    applyResolved,
    applyAck,
    applyDeviceRegistered,
  };
};
